//
//  coderpadTests+MCPPadAggregation.swift
//  coderpadTests
//
//  Tests for the in-app MCP server's count/aggregate/compact transforms (#500):
//  filtering, grouping, ordering, and the compact projection. Pure, so tested without
//  network.
//

@testable import CoderPad
import Foundation
import Testing

@Suite("MCP pad aggregation")
struct MCPPadAggregationTests {
    private let pads: [[String: Any]] = [
        ["owner_email": "a@x.com", "state": "active", "language": "python", "created_at": "2026-01-04T00:00:00Z"],
        ["owner_email": "A@x.com", "state": "ended", "language": "Python", "created_at": "2026-01-20T00:00:00Z"],
        ["owner_email": "b@x.com", "state": "active", "language": "ruby", "created_at": "2026-02-02T00:00:00Z"],
        ["state": "active", "language": "ruby"]
    ]

    @Test
    func `a schema-invalid list response becomes an explicit error, not empty data (#829, #830)`() {
        let outcome = MCPTools.invalidListResponse(
            "/api/pads/", expecting: "pads",
            body: "<html>upstream unavailable</html>"
        )
        #expect(outcome.isError)
        #expect(outcome.text.contains("/api/pads/"))
        #expect(outcome.text.contains("\"pads\""))
        #expect(outcome.text.contains("upstream unavailable"))
    }

    @Test
    func `the invalid-response preview is capped so an HTML page can't flood the reply`() {
        let outcome = MCPTools.invalidListResponse(
            "/api/pads/", expecting: "pads",
            body: String(repeating: "x", count: 5000)
        )
        #expect(outcome.isError)
        #expect(outcome.text.count < 600)
    }

    @Test
    func `nextPageToken reads strings and ints, nil when absent or empty`() {
        #expect(nextPageToken("abc") == "abc")
        #expect(nextPageToken(2) == "2")
        #expect(nextPageToken("") == nil)
        #expect(nextPageToken(nil) == nil)
    }

    @Test
    func `matches is case-insensitive and treats empty filters as wildcards`() {
        #expect(padMatches(pads[0], owner: "A@X.COM", state: nil, language: nil))
        #expect(padMatches(pads[0], owner: nil, state: "active", language: "PYTHON"))
        #expect(!padMatches(pads[0], owner: "b@x.com", state: nil, language: nil))
        #expect(padMatches(pads[0], owner: "", state: "", language: ""))
        #expect(!padMatches(pads[3], owner: "a@x.com", state: nil, language: nil))
    }

    @Test
    func `state filter folds API synonyms so "active" matches "started" (#1014)`() {
        let started: [String: Any] = ["state": "started", "language": "python3"]
        #expect(padMatches(started, owner: nil, state: "active", language: nil))
        #expect(padMatches(started, owner: nil, state: "Started", language: nil))
        #expect(!padMatches(started, owner: nil, state: "ended", language: nil))
        let finished: [String: Any] = ["state": "finished"]
        #expect(padMatches(finished, owner: nil, state: "ended", language: nil))

        #expect(canonicalPadState("running") == "active")
        #expect(canonicalPadState("draft") == "pending")
        #expect(canonicalPadState("Deleted") == "deleted")
        #expect(canonicalPadState("weird") == "weird")
    }

    @Test
    func `state aggregation buckets by canonical spelling (#1014)`() {
        let raw: [[String: Any]] = [
            ["state": "started"], ["state": "active"], ["state": "finished"], ["state": "ended"]
        ]
        let counts = aggregateCounts(pads: raw, field: "state")
        #expect(counts == ["active": 2, "ended": 2])
    }

    @Test
    func `aggregateField normalizes synonyms and rejects unknown`() {
        #expect(aggregateField(for: "owner") == "owner_email")
        #expect(aggregateField(for: "Created_At") == "month")
        #expect(aggregateField(for: "bogus") == nil)
    }

    @Test
    func `counts canonicalize owners and bucket months by YYYY-MM, missing -> unknown`() {
        let owners = aggregateCounts(pads: pads, field: "owner_email")
        #expect(owners["a@x.com"] == 2)
        #expect(owners["A@x.com"] == nil)
        #expect(owners["unknown"] == 1)

        let languages = aggregateCounts(
            pads: [["language": "Swift"], ["language": " swift "]],
            field: "language"
        )
        #expect(languages == ["swift": 2])

        let months = aggregateCounts(pads: pads, field: "month")
        #expect(months["2026-01"] == 2)
        #expect(months["2026-02"] == 1)
        #expect(months["unknown"] == 1)
    }

    @Test
    func `accumulateCounts page by page matches tallying the whole list (#2121)`() {
        var running: [String: Int] = [:]
        for page in [Array(pads.prefix(2)), Array(pads.dropFirst(2))] {
            accumulateCounts(&running, pads: page, field: "month")
        }
        #expect(running == aggregateCounts(pads: pads, field: "month"))
    }

    @Test
    func `topGroups sorts by count desc then key asc, and caps`() {
        let top = topGroups(["python": 5, "ruby": 5, "go": 3, "rust": 1], limit: 3)
        #expect(top == [
            AggregateGroup(value: "python", count: 5),
            AggregateGroup(value: "ruby", count: 5),
            AggregateGroup(value: "go", count: 3)
        ])
    }

    @Test
    func `withinDateRange honors month, date and timestamp bounds, inclusively`() {
        let pad = pads[0] // created_at 2026-01-04T00:00:00Z
        // Absent/empty bounds always pass.
        #expect(withinDateRange(pad, after: nil, before: nil))
        #expect(withinDateRange(pad, after: "", before: ""))
        // Month-granularity bounds are inclusive.
        #expect(withinDateRange(pad, after: "2026-01", before: "2026-01"))
        #expect(!withinDateRange(pad, after: "2026-02", before: nil))
        #expect(!withinDateRange(pad, after: nil, before: "2025-12"))
        // Date-granularity bounds, inclusive on the day.
        #expect(withinDateRange(pad, after: "2026-01-04", before: "2026-01-04"))
        #expect(!withinDateRange(pad, after: "2026-01-05", before: nil))
        // A record with no created_at fails any present bound.
        #expect(!withinDateRange(pads[3], after: "2026-01", before: nil))
        #expect(withinDateRange(pads[3], after: nil, before: nil))
    }

    @Test
    func `month buckets and month-date bounds normalize non-UTC created_at (#1034, #1035)`() {
        // 2024-03-31T23:00-05:00 is 2024-04-01T04:00Z: it must bucket and filter as
        // April in UTC regardless of the offset spelling the source used.
        let offset: [String: Any] = ["created_at": "2024-03-31T23:00:00-05:00"]
        let utc: [String: Any] = ["created_at": "2024-04-01T04:00:00Z"]

        let months = aggregateCounts(pads: [offset, utc], field: "month")
        #expect(months == ["2024-04": 2])

        #expect(withinDateRange(offset, after: "2024-04", before: nil))
        #expect(!withinDateRange(offset, after: nil, before: "2024-03-31"))
        #expect(withinDateRange(offset, after: "2024-04-01", before: "2024-04-01"))
        #expect(withinDateRange(utc, after: "2024-04", before: nil))
    }

    @Test
    func `withinDateRange compares timestamp offsets chronologically`() {
        let record = ["created_at": "2026-03-01T00:00:00Z"]

        #expect(withinDateRange(record, after: "2026-03-01T01:00:00+02:00", before: nil))
        #expect(!withinDateRange(record, after: "2026-03-01T03:00:00+02:00", before: nil))
        #expect(withinDateRange(record, after: nil, before: "2026-02-28T22:30:00-02:00"))
        #expect(!withinDateRange(record, after: nil, before: "2026-02-28T21:30:00-02:00"))
    }

    @Test
    func `date bound validation rejects malformed bounds`() {
        #expect(dateBoundValidationError(after: nil, before: "") == nil)
        #expect(dateBoundValidationError(after: "2026-01", before: "2026-01-31") == nil)
        #expect(dateBoundValidationError(after: "2026-01-04T00:00:00Z", before: nil) == nil)
        #expect(dateBoundValidationError(after: "yesterday", before: nil)?.contains("created_after") == true)
        #expect(dateBoundValidationError(after: "2026-99-99", before: nil)?.contains("created_after") == true)
        #expect(dateBoundValidationError(after: nil, before: "2026-02-31")?.contains("created_before") == true)
    }

    @Test
    func `compact keeps only the compact keys`() {
        let rich: [[String: Any]] = [[
            "id": "abc", "title": "T", "owner_email": "a@x.com", "state": "active",
            "language": "python", "created_at": "2026-01-01", "contents": "blob", "notes": "secret"
        ]]
        let compact = compactPads(rich)
        #expect(Set(compact[0].keys) == Set(compactPadKeys))
        #expect(compact[0]["contents"] == nil)
    }

    /// Proxies can re-encode the token as another numeric form or pad it with
    /// whitespace; neither must silently end pagination (#1599). Booleans are
    /// not tokens.
    @Test
    func `nextPageToken accepts numeric forms and trims strings`() {
        #expect(nextPageToken(" 7 ") == "7")
        #expect(nextPageToken("   ") == nil)
        #expect(nextPageToken(Int64(3)) == "3")
        #expect(nextPageToken(3.5) == "3.5")
        #expect(nextPageToken(true) == nil)
    }

    /// Filter inputs and API values are trimmed before matching, and padded
    /// state values fold to their canonical spelling (#1600, #1601).
    @Test
    func `matches trims whitespace-padded arguments and API values`() {
        #expect(padMatches(pads[0], owner: " a@x.com ", state: nil, language: nil))
        #expect(padMatches(pads[0], owner: nil, state: " ACTIVE ", language: " python "))
        #expect(padMatches(pads[0], owner: "   ", state: nil, language: nil))
        #expect(canonicalPadState(" started ") == "active")
    }

    /// An error page echoing a long token-shaped run must not flow to the MCP
    /// client (#1602).
    @Test
    func `the invalid-response preview redacts token-shaped runs`() {
        let body = "unauthorized: api key sk-EXAMPLEEXAMPLEEXAMPLEEXAMPLE was rejected"
        let message = invalidListResponseMessage("/pads", expecting: "pads", body: body)
        #expect(!message.contains("EXAMPLEEXAMPLE"))
        #expect(message.contains("[redacted]"))
    }

    /// An inverted range is a caller error, not a legitimate empty result
    /// (#1604). Month/date bounds count as whole inclusive periods.
    @Test
    func `date bound validation rejects inverted ranges`() {
        #expect(dateBoundValidationError(after: "2025-02", before: "2025-01") != nil)
        #expect(dateBoundValidationError(after: "2025-01-02", before: "2025-01-01") != nil)
        // The same month is a valid one-month window, not an inversion.
        #expect(dateBoundValidationError(after: "2025-01", before: "2025-01") == nil)
        // A timestamp inside the before-month's period is fine.
        #expect(dateBoundValidationError(after: "2025-01-20T00:00:00Z", before: "2025-01") == nil)
        #expect(dateBoundValidationError(after: "2025-01", before: "2025-12") == nil)
    }

    /// Remote fields are untrusted: group keys are capped in length and
    /// cardinality, and the group limit is clamped (#1606, #1607).
    @Test
    func `aggregation bounds group keys, cardinality, and limits`() {
        let longOwner = String(repeating: "a", count: 500)
        let counts = aggregateCounts(pads: [["owner_email": longOwner]], field: "owner_email")
        #expect(counts.keys.allSatisfy { $0.count <= maxAggregateKeyLength })

        let many = (0 ..< (maxAggregateGroups + 5)).map { ["owner_email": "owner\($0)@x.com"] }
        let capped = aggregateCounts(pads: many, field: "owner_email")
        #expect(capped.count <= maxAggregateGroups + 1)
        #expect(capped["other"] == 5)

        #expect(topGroups(["a": 1], limit: -3).isEmpty)
    }

    /// A response nesting a huge object under an allowed key would defeat the
    /// compact projection (#1608).
    @Test
    func `compact drops nested values and caps strings`() {
        let rows = compactPads([["id": "P1", "title": ["nested": "blob"], "state": "started"]])
        #expect(rows[0]["id"] as? String == "P1")
        #expect(rows[0]["title"] == nil)
        let long = compactPads([["title": String(repeating: "x", count: 5000)]])
        #expect((long[0]["title"] as? String)?.count ?? 0 <= 1001)
    }
}
