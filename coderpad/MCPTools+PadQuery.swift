//
//  MCPTools+PadQuery.swift
//  coderpad
//
//  The pad count / aggregate / compact tools for the in-app MCP server (#500): page
//  the pad list internally and tally/project in-process, so "how many pads match X"
//  returns a small answer instead of streaming every verbose record through the model.
//  Split out of MCPTools.swift to keep that file within its length budget. The pure
//  transforms live in MCPPadAggregation.
//

import Foundation

nonisolated extension MCPTools {
    /// Encodes a result dictionary as pretty JSON text.
    private static func jsonResult(_ object: [String: Any]) -> Outcome {
        guard let data = try? JSONSerialization.data(
            withJSONObject: object, options: [.prettyPrinted, .sortedKeys]
        ) else {
            return Outcome(text: "Could not encode the result.", isError: true)
        }

        return Outcome(text: String(bytes: data, encoding: .utf8) ?? "", isError: false)
    }

    // MARK: - count_pads / aggregate_pads / list_pads_compact (#500)

    /// Safety cap on internal paging so a huge org (or a paging bug) can't loop forever.
    private static let maxPadPagesToFetch = 500

    /// At most this many groups are returned by aggregate_pads.
    private static let maxAggregateGroups = 200

    /// The result of paging the whole pad list internally.
    private struct PadScan {
        var pads: [[String: Any]] = []
        var totalReported: Int?
        var pagesFetched = 0
        var truncated = false
        var fromCache = false
        var error: Outcome?
    }

    /// Gets every pad for the account so the count/aggregate tools can tally in-process.
    /// Prefers PadBuddy's fresh on-disk cache (#520) — one read instead of paging the whole
    /// org through the API — and falls back to paging the API, then to a stale cache when
    /// the API can't be reached (offline).
    private static func fetchAllPads(accountID: String, key: String, base: URL) async -> PadScan {
        if let cached = cachedPadDicts(accountID: accountID, requireFresh: true) {
            return PadScan(pads: cached, totalReported: cached.count, fromCache: true)
        }

        let scan = await pageAllPadsFromAPI(key: key, base: base)
        if scan.error != nil, let cached = cachedPadDicts(accountID: accountID, requireFresh: false) {
            return PadScan(pads: cached, totalReported: cached.count, fromCache: true)
        }
        return scan
    }

    /// Pages `/api/pads/` from the first page following `next_page`, accumulating every pad.
    private static func pageAllPadsFromAPI(key: String, base: URL) async -> PadScan {
        var scan = PadScan()
        var page: String?
        while scan.pagesFetched < maxPadPagesToFetch {
            var query: [URLQueryItem] = []
            if let page { query.append(URLQueryItem(name: "page", value: page)) }
            let response = await get("/api/pads/", key: key, base: base, query: query)
            guard !response.isError, let object = jsonObject(response.text) else {
                scan.error = response
                return scan
            }

            if scan.totalReported == nil { scan.totalReported = object["total"] as? Int }
            if let pads = object["pads"] as? [[String: Any]] { scan.pads.append(contentsOf: pads) }
            scan.pagesFetched += 1
            guard let next = MCPPadAggregation.nextPageToken(object["next_page"]) else { return scan }

            page = next
        }

        scan.truncated = true
        return scan
    }

    static func countPads(arguments: [String: Any], credentials: MCPCredentials) async -> Outcome {
        let owner = string(arguments, "owner")
        let state = string(arguments, "state")
        let language = string(arguments, "language")
        let after = string(arguments, "created_after")
        let before = string(arguments, "created_before")

        let scan = await fetchAllPads(accountID: credentials.id, key: credentials.apiKey, base: credentials.baseURL)
        if let error = scan.error { return error }

        let matched = scan.pads.filter {
            MCPPadAggregation.matches($0, owner: owner, state: state, language: language)
                && MCPPadAggregation.withinDateRange($0, after: after, before: before)
        }
        var result: [String: Any] = [
            "matched": matched.count,
            "scanned": scan.pads.count,
            "pages_fetched": scan.pagesFetched,
            "truncated": scan.truncated,
            "source": scan.fromCache ? "padbuddy_cache" : "coderpad_api"
        ]
        if let total = scan.totalReported { result["total_reported_by_api"] = total }
        var filters = MCPPadAggregation.filtersEcho(owner: owner, state: state, language: language)
        MCPPadAggregation.addDateFilters(&filters, after: after, before: before)
        if !filters.isEmpty { result["filters"] = filters }
        if scan.truncated {
            result["note"] = "Hit the internal page cap (\(maxPadPagesToFetch) pages); "
                + "the count covers only the pads scanned."
        }

        return jsonResult(result)
    }

    static func aggregatePads(
        groupBy: String, arguments: [String: Any], credentials: MCPCredentials
    ) async -> Outcome {
        guard let field = MCPPadAggregation.aggregateField(for: groupBy) else {
            return Outcome(
                text: "Unsupported group_by \"\(groupBy)\". Use owner, language, state, or month.",
                isError: true
            )
        }

        let owner = string(arguments, "owner")
        let state = string(arguments, "state")
        let language = string(arguments, "language")
        let after = string(arguments, "created_after")
        let before = string(arguments, "created_before")

        let scan = await fetchAllPads(accountID: credentials.id, key: credentials.apiKey, base: credentials.baseURL)
        if let error = scan.error { return error }

        let matched = scan.pads.filter {
            MCPPadAggregation.matches($0, owner: owner, state: state, language: language)
                && MCPPadAggregation.withinDateRange($0, after: after, before: before)
        }
        let counts = MCPPadAggregation.counts(pads: matched, field: field)
        let capped = MCPPadAggregation.topGroups(counts, limit: maxAggregateGroups)
        let groups: [[String: Any]] = capped.map { ["value": $0.value, "count": $0.count] }

        var result: [String: Any] = [
            "group_by": field,
            "matched": matched.count,
            "scanned": scan.pads.count,
            "distinct_groups": counts.count,
            "groups": groups,
            "pages_fetched": scan.pagesFetched,
            "truncated": scan.truncated,
            "source": scan.fromCache ? "padbuddy_cache" : "coderpad_api"
        ]
        var filters = MCPPadAggregation.filtersEcho(owner: owner, state: state, language: language)
        MCPPadAggregation.addDateFilters(&filters, after: after, before: before)
        if !filters.isEmpty { result["filters"] = filters }
        if counts.count > capped.count {
            result["groups_truncated"] = true
            result["note"] = "Showing the top \(capped.count) of \(counts.count) groups by count."
        }

        return jsonResult(result)
    }

    static func listPadsCompact(arguments: [String: Any], key: String, base: URL) async -> Outcome {
        let response = await get("/api/pads/", key: key, base: base, query: paging(arguments))
        guard !response.isError, let object = jsonObject(response.text) else { return response }

        let pads = (object["pads"] as? [[String: Any]]) ?? []
        var result: [String: Any] = ["pads": MCPPadAggregation.compact(pads), "count": pads.count]
        if let next = object["next_page"], !(next is NSNull) { result["next_page"] = next }
        if let total = object["total"], !(total is NSNull) { result["total"] = total }

        return jsonResult(result)
    }
}
