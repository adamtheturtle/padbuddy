//
//  MCPTools+Cache.swift
//  coderpad
//
//  Backs the in-app MCP read tools with PadBuddy's on-disk caches (#520). The headless
//  `--mcp` process is a separate launch from the running app, but it shares the same
//  sandbox container, so it can read the very snapshots the app wrote (`CacheDisk`,
//  pads + questions). Two strategies, chosen per tool:
//
//  - Full-scan tools (count_pads / aggregate_pads): cache-FIRST when the snapshot is
//    fresh, so a large org isn't re-paged from the API on every call (pairs with #500),
//    falling back to the API and then to a stale snapshot when offline.
//  - Single-record tools (get_pad / get_question): API-FIRST (the single GET is one fast,
//    richer call), with the cache as an OFFLINE fallback.
//
//  Only pads and questions are disk-backed; org and quota are memory-only in the app, so
//  the headless process can't read them and those tools stay API-only.
//

import Foundation

nonisolated extension MCPTools {
    /// How recently the app must have written a snapshot for a full-scan tool to serve it
    /// without hitting the API. Older than this and we re-fetch (but still fall back to the
    /// stale snapshot if the network is down).
    static let cacheFreshness: TimeInterval = 10 * 60

    /// Cached pads for an account, optionally only when fresh. nil when there's no readable
    /// snapshot (no file, wrong account id, or a decode failure).
    static func cachedPads(accountID: String, requireFresh: Bool) -> [Pad]? {
        guard let account = UUID(uuidString: accountID) else { return nil }

        if requireFresh, !isCacheFresh(kind: "pads", account: account) { return nil }

        return CacheDisk.load([Pad].self, kind: "pads", account: account)
    }

    /// Cached questions for an account (see `cachedPads`).
    static func cachedQuestions(accountID: String, requireFresh: Bool) -> [Question]? {
        guard let account = UUID(uuidString: accountID) else { return nil }

        if requireFresh, !isCacheFresh(kind: "questions", account: account) { return nil }

        return CacheDisk.load([Question].self, kind: "questions", account: account)
    }

    /// Cached pads as API-shaped dictionaries (snake_case keys, ISO8601 dates) so they feed
    /// the existing aggregation pipeline exactly like freshly-paged API records.
    static func cachedPadDicts(accountID: String, requireFresh: Bool) -> [[String: Any]]? {
        guard let pads = cachedPads(accountID: accountID, requireFresh: requireFresh),
              let data = try? apiShapedEncoder.encode(pads),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }

        return array
    }

    /// Cached questions as API-shaped dictionaries (snake_case keys, ISO8601 dates) so they
    /// feed the question aggregation pipeline exactly like freshly-paged API records.
    static func cachedQuestionDicts(accountID: String, requireFresh: Bool) -> [[String: Any]]? {
        guard let questions = cachedQuestions(accountID: accountID, requireFresh: requireFresh),
              let data = try? apiShapedEncoder.encode(questions),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }

        return array
    }

    /// get_pad backed by the cache: the live single GET first (it's one fast call and the
    /// detail record is the richest), then the cached snapshot if the request fails so a
    /// known pad still answers offline.
    static func getPadCacheBacked(pad: String, credentials: MCPCredentials) async -> Outcome {
        let live = await get("/api/pads/\(pad)", key: credentials.apiKey, base: credentials.baseURL)
        // Fall back to the snapshot only when the API was unreachable: an HTTP error
        // (401 from a revoked key, a genuine 404) must be surfaced, not answered from
        // the cache (#828).
        guard live.isConnectivityFailure else { return live }

        if let pads = cachedPads(accountID: credentials.id, requireFresh: false),
           let match = pads.first(where: { $0.id == pad }),
           let text = jsonText(match) {
            return Outcome(text: text, isError: false)
        }
        return live
    }

    /// get_question backed by the cache (see `getPadCacheBacked`).
    static func getQuestionCacheBacked(id: Int, credentials: MCPCredentials) async -> Outcome {
        let live = await get("/api/questions/\(id)", key: credentials.apiKey, base: credentials.baseURL)
        // See getPadCacheBacked: offline-only fallback (#828).
        guard live.isConnectivityFailure else { return live }

        if let questions = cachedQuestions(accountID: credentials.id, requireFresh: false),
           let match = questions.first(where: { $0.id == id }),
           let text = jsonText(match) {
            return Outcome(text: text, isError: false)
        }
        return live
    }

    /// Encodes a value to JSON text with ISO8601 dates, matching the API's representation
    /// so a cache-served record reads the same as a live one.
    static func jsonText(_ value: some Encodable) -> String? {
        guard let data = try? apiShapedEncoder.encode(value) else { return nil }

        return String(bytes: data, encoding: .utf8)
    }

    /// Whether the snapshot for `kind`+`account` was written within `cacheFreshness`.
    private static func isCacheFresh(kind: String, account: UUID) -> Bool {
        guard let written = CacheDisk.modificationDate(kind: kind, account: account) else { return false }

        return Date().timeIntervalSince(written) <= cacheFreshness
    }

    /// A JSON encoder that emits ISO8601 dates, so cache-encoded records carry `created_at`
    /// as the same string form the API sends (the month aggregation reads its `YYYY-MM`).
    private static var apiShapedEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
