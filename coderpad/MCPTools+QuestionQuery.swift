//
//  MCPTools+QuestionQuery.swift
//  coderpad
//
//  The question count / aggregate / compact tools for the in-app MCP server (#500),
//  mirroring MCPTools+PadQuery for the question bank: page /api/questions/ internally and
//  tally or project in-process, so "how many questions by language / author" returns a
//  small answer instead of streaming every verbose record through the model. The pure
//  transforms live in the shared CoderPadToolCore package (#521); the question helpers
//  reuse the pad ones' field-agnostic counts/topGroups/nextPageToken).
//

import Foundation

nonisolated extension MCPTools {
    /// Routes a question count/aggregate/compact tool, falling through to `listOrSummary`
    /// for the plain GETs. Takes the whole `credentials` because the count/aggregate tools
    /// also read the account's on-disk cache (#520), keyed by account id.
    static func questionQuery(
        name: String, arguments: [String: Any], credentials: MCPCredentials
    ) async -> Outcome {
        switch name {
        case "count_questions":
            return await countQuestions(arguments: arguments, credentials: credentials)

        case "aggregate_questions":
            guard let groupBy = string(arguments, "group_by") else { return missing("group_by") }

            return await aggregateQuestions(groupBy: groupBy, arguments: arguments, credentials: credentials)

        case "list_questions_compact":
            return await listQuestionsCompact(
                arguments: arguments, key: credentials.apiKey, base: credentials.baseURL
            )

        default:
            return await listOrSummary(
                name: name, arguments: arguments, key: credentials.apiKey, base: credentials.baseURL
            )
        }
    }

    /// Safety cap on internal paging so a huge bank (or a paging bug) can't loop forever.
    private static let maxQuestionPagesToFetch = 500

    /// At most this many groups are returned by aggregate_questions.
    private static let maxQuestionGroups = 200

    /// The result of paging the whole question bank internally.
    private struct QuestionScan {
        var questions: [[String: Any]] = []
        var totalReported: Int?
        var pagesFetched = 0
        var truncated = false
        var fromCache = false
        var error: Outcome?
    }

    /// Gets every question for the account so the count/aggregate tools can tally
    /// in-process. Prefers PadBuddy's fresh on-disk cache (#520) — one read instead of
    /// paging the whole bank through the API — and falls back to paging the API, then to a
    /// stale cache when the API can't be reached (offline).
    private static func fetchAllQuestions(accountID: String, key: String, base: URL) async -> QuestionScan {
        // A cache-served scan carries no totalReported: that field is reserved for the
        // API's own "total", so `total_reported_by_api` never claims API provenance for
        // a local snapshot count (#1028). `scanned` already reports the snapshot size.
        if let cached = cachedQuestionDicts(accountID: accountID, requireFresh: true) {
            return QuestionScan(questions: cached, fromCache: true)
        }

        let scan = await pageAllQuestionsFromAPI(key: key, base: base)
        // Only a transport failure (offline) justifies the stale-cache fallback: an HTTP
        // error, e.g. a 401 from a revoked key, must be surfaced, not papered over with
        // cached content (#828).
        if scan.error?.isConnectivityFailure == true,
           let cached = cachedQuestionDicts(accountID: accountID, requireFresh: false) {
            return QuestionScan(questions: cached, fromCache: true)
        }
        return scan
    }

    /// Pages `/api/questions/` from the first page following `next_page`, accumulating every
    /// question.
    private static func pageAllQuestionsFromAPI(key: String, base: URL) async -> QuestionScan {
        var scan = QuestionScan()
        var page: String?
        var tokens = PaginationTokenTracker()
        while scan.pagesFetched < maxQuestionPagesToFetch {
            var query: [URLQueryItem] = []
            if let page { query.append(URLQueryItem(name: "page", value: page)) }
            let response = await get("/api/questions/", key: key, base: base, query: query)
            guard !response.isError else {
                scan.error = response
                return scan
            }

            // A 2xx body without the required shape is an explicit error, never an
            // empty page: silently counting zero rows would be wrong (#829, #830).
            guard let object = jsonObject(response),
                  let questions = object["questions"] as? [[String: Any]]
            else {
                scan.error = invalidListResponse("/api/questions/", expecting: "questions", body: response.text)
                return scan
            }

            if scan.totalReported == nil { scan.totalReported = object["total"] as? Int }
            scan.questions.append(contentsOf: questions)
            scan.pagesFetched += 1
            guard let next = nextPageToken(object["next_page"]) else { return scan }
            guard tokens.accept(next) else {
                scan.error = Outcome(
                    text: "Question pagination repeated next_page token \"\(next)\"; the scan is incomplete.",
                    isError: true
                )
                return scan
            }

            page = next
        }

        scan.truncated = true
        return scan
    }

    static func countQuestions(arguments: [String: Any], credentials: MCPCredentials) async -> Outcome {
        let owner = string(arguments, "owner")
        let author = string(arguments, "author")
        let language = string(arguments, "language")
        let type = string(arguments, "type")
        let after = string(arguments, "created_after")
        let before = string(arguments, "created_before")
        if let error = dateBoundValidationError(after: after, before: before) {
            return Outcome(text: error, isError: true)
        }

        let scan = await fetchAllQuestions(
            accountID: credentials.id, key: credentials.apiKey, base: credentials.baseURL
        )
        if let error = scan.error { return error }

        // Built once for the whole list rather than re-normalizing the filter
        // values for every row (#2452, #2453).
        let matcher = QuestionMatcher(owner: owner, author: author, language: language, type: type)
        // Counted, not collected: only the count is ever read, and materializing the
        // whole matched array meant allocating a second copy of every matching record
        // on a large org just to measure it (#2243).
        let matched = scan.questions.count {
            matcher.matches($0)
                && withinDateRange($0, after: after, before: before)
        }
        var result: [String: Any] = [
            "matched": matched,
            "scanned": scan.questions.count,
            "pages_fetched": scan.pagesFetched,
            "truncated": scan.truncated,
            "source": scan.fromCache ? "padbuddy_cache" : "coderpad_api"
        ]
        if let total = scan.totalReported { result["total_reported_by_api"] = total }
        var filters = questionFiltersEcho(owner: owner, author: author, language: language, type: type)
        addDateFilters(&filters, after: after, before: before)
        if !filters.isEmpty { result["filters"] = filters }
        if scan.truncated {
            result["note"] = "Hit the internal page cap (\(maxQuestionPagesToFetch) pages); "
                + "the count covers only the questions scanned."
        }

        return questionJSONResult(result)
    }

    static func aggregateQuestions(
        groupBy: String, arguments: [String: Any], credentials: MCPCredentials
    ) async -> Outcome {
        guard let field = questionAggregateField(for: groupBy) else {
            return Outcome(
                text: "Unsupported group_by \"\(groupBy)\". Use owner, author, language, type, or month.",
                isError: true
            )
        }

        let owner = string(arguments, "owner")
        let author = string(arguments, "author")
        let language = string(arguments, "language")
        let type = string(arguments, "type")
        let after = string(arguments, "created_after")
        let before = string(arguments, "created_before")
        if let error = dateBoundValidationError(after: after, before: before) {
            return Outcome(text: error, isError: true)
        }

        let scan = await fetchAllQuestions(
            accountID: credentials.id, key: credentials.apiKey, base: credentials.baseURL
        )
        if let error = scan.error { return error }

        // Built once for the whole list rather than re-normalizing the filter
        // values for every row (#2452, #2453).
        let matcher = QuestionMatcher(owner: owner, author: author, language: language, type: type)
        let matched = scan.questions.filter {
            matcher.matches($0)
                && withinDateRange($0, after: after, before: before)
        }
        let counts = aggregateCounts(pads: matched, field: field)
        let capped = topGroups(counts, limit: maxQuestionGroups)
        let groups: [[String: Any]] = capped.map { ["value": $0.value, "count": $0.count] }

        var result: [String: Any] = [
            "group_by": field,
            "matched": matched.count,
            "scanned": scan.questions.count,
            "distinct_groups": counts.count,
            "groups": groups,
            "pages_fetched": scan.pagesFetched,
            "truncated": scan.truncated,
            "source": scan.fromCache ? "padbuddy_cache" : "coderpad_api"
        ]
        var filters = questionFiltersEcho(owner: owner, author: author, language: language, type: type)
        addDateFilters(&filters, after: after, before: before)
        if !filters.isEmpty { result["filters"] = filters }
        if counts.count > capped.count {
            result["groups_truncated"] = true
            result["note"] = "Showing the top \(capped.count) of \(counts.count) groups by count."
        }

        return questionJSONResult(result)
    }

    static func listQuestionsCompact(arguments: [String: Any], key: String, base: URL) async -> Outcome {
        if let error = pageValidationError(int(arguments, "page")) {
            return Outcome(text: error, isError: true)
        }

        let response = await get("/api/questions/", key: key, base: base, query: paging(arguments))
        guard !response.isError else { return response }
        guard let object = jsonObject(response),
              let questions = object["questions"] as? [[String: Any]]
        else { return invalidListResponse("/api/questions/", expecting: "questions", body: response.text) }

        var result: [String: Any] = [
            "questions": compactQuestions(questions), "count": questions.count
        ]
        if let next = object["next_page"], !(next is NSNull) { result["next_page"] = next }
        if let total = object["total"], !(total is NSNull) { result["total"] = total }

        return questionJSONResult(result)
    }

    /// Encodes a result dictionary as pretty JSON text. Mirrors the private helper in
    /// MCPTools+PadQuery; kept here too so each query file stays self-contained.
    private static func questionJSONResult(_ object: [String: Any]) -> Outcome {
        guard let data = try? JSONSerialization.data(
            withJSONObject: object, options: [.prettyPrinted, .sortedKeys]
        ) else {
            return Outcome(text: "Could not encode the result.", isError: true)
        }

        return Outcome(text: String(bytes: data, encoding: .utf8) ?? "", isError: false)
    }
}
