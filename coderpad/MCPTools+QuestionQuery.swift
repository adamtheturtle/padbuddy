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

import BuddyMCP
import Foundation

nonisolated extension MCPTools {
    /// The question count/aggregate/compact tool descriptors (#500), appended to the read
    /// tools by `MCPTools.readTools`. Kept here (not in the main type body) so MCPTools
    /// stays within its type-body length budget.
    static var questionReadTools: [[String: Any]] {
        [
            tool("count_questions",
                 "Count questions in the bank, optionally filtered, WITHOUT returning the "
                     + "records — one cheap call instead of paging every verbose record. Served "
                     + "from PadBuddy's local cache when it's fresh (and offline), else paged "
                     + "live; the response's `source` field says which.",
                 properties: questionFilterProperties.merging([account: accountSchema]) { _, new in new }),
            tool("aggregate_questions",
                 "Group questions by a field and return only the counts (not the records) — "
                     + "e.g. how many questions per language or author, over a large bank, "
                     + "without blowing context. Uses PadBuddy's local cache when fresh (see "
                     + "the `source` field).",
                 properties: questionFilterProperties.merging([
                     "group_by": stringSchema("Field to group by: owner, author, language, type, or month."),
                     account: accountSchema
                 ]) { _, new in new },
                 required: ["group_by"]),
            tool("list_questions_compact",
                 "Like list_questions but returns only id, title, owner_email, author_name, "
                     + "language, pad_type, is_draft, and created_at per question, so far more "
                     + "rows fit per response.",
                 properties: ["page": intSchema("1-based page number."),
                              "sort": stringSchema("Sort order."),
                              account: accountSchema])
        ]
    }

    /// The owner/author/language/type filters shared by count_questions and
    /// aggregate_questions. The bank API has no server-side filters, so these are applied
    /// in-process while paging.
    private static var questionFilterProperties: [String: [String: Any]] {
        [
            "owner": stringSchema("Only questions whose owner_email matches this, case-insensitively."),
            "author": stringSchema("Only questions whose author_name matches this, case-insensitively."),
            "language": stringSchema("Only questions in this language (e.g. \"python\")."),
            "type": stringSchema("Only questions of this pad_type (e.g. \"sandbox\", \"take_home\")."),
            "created_after": stringSchema(dateBoundDescription(bound: "on or after")),
            "created_before": stringSchema(dateBoundDescription(bound: "on or before"))
        ]
    }

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
        if let cached = cachedQuestionDicts(accountID: accountID, requireFresh: true) {
            return QuestionScan(questions: cached, totalReported: cached.count, fromCache: true)
        }

        let scan = await pageAllQuestionsFromAPI(key: key, base: base)
        if scan.error != nil, let cached = cachedQuestionDicts(accountID: accountID, requireFresh: false) {
            return QuestionScan(questions: cached, totalReported: cached.count, fromCache: true)
        }
        return scan
    }

    /// Pages `/api/questions/` from the first page following `next_page`, accumulating every
    /// question.
    private static func pageAllQuestionsFromAPI(key: String, base: URL) async -> QuestionScan {
        var scan = QuestionScan()
        var page: String?
        while scan.pagesFetched < maxQuestionPagesToFetch {
            var query: [URLQueryItem] = []
            if let page { query.append(URLQueryItem(name: "page", value: page)) }
            let response = await get("/api/questions/", key: key, base: base, query: query)
            guard !response.isError, let object = jsonObject(response.text) else {
                scan.error = response
                return scan
            }

            if scan.totalReported == nil { scan.totalReported = object["total"] as? Int }
            if let questions = object["questions"] as? [[String: Any]] { scan.questions.append(contentsOf: questions) }
            scan.pagesFetched += 1
            guard let next = nextPageToken(object["next_page"]) else { return scan }

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

        let scan = await fetchAllQuestions(
            accountID: credentials.id, key: credentials.apiKey, base: credentials.baseURL
        )
        if let error = scan.error { return error }

        let matched = scan.questions.filter {
            questionMatches($0, owner: owner, author: author, language: language, type: type)
                && withinDateRange($0, after: after, before: before)
        }
        var result: [String: Any] = [
            "matched": matched.count,
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

        let scan = await fetchAllQuestions(
            accountID: credentials.id, key: credentials.apiKey, base: credentials.baseURL
        )
        if let error = scan.error { return error }

        let matched = scan.questions.filter {
            questionMatches($0, owner: owner, author: author, language: language, type: type)
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
        let response = await get("/api/questions/", key: key, base: base, query: paging(arguments))
        guard !response.isError, let object = jsonObject(response.text) else { return response }

        let questions = (object["questions"] as? [[String: Any]]) ?? []
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
