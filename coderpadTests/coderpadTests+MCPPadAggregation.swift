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
    func `aggregateField normalizes synonyms and rejects unknown`() {
        #expect(aggregateField(for: "owner") == "owner_email")
        #expect(aggregateField(for: "Created_At") == "month")
        #expect(aggregateField(for: "bogus") == nil)
    }

    @Test
    func `counts bucket owners as stored and months by YYYY-MM, missing -> unknown`() {
        let owners = aggregateCounts(pads: pads, field: "owner_email")
        #expect(owners["a@x.com"] == 1)
        #expect(owners["A@x.com"] == 1)
        #expect(owners["unknown"] == 1)

        let months = aggregateCounts(pads: pads, field: "month")
        #expect(months["2026-01"] == 2)
        #expect(months["2026-02"] == 1)
        #expect(months["unknown"] == 1)
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
}
