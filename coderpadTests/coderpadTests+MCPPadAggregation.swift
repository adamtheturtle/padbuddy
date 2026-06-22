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
        #expect(MCPPadAggregation.nextPageToken("abc") == "abc")
        #expect(MCPPadAggregation.nextPageToken(2) == "2")
        #expect(MCPPadAggregation.nextPageToken("") == nil)
        #expect(MCPPadAggregation.nextPageToken(nil) == nil)
    }

    @Test
    func `matches is case-insensitive and treats empty filters as wildcards`() {
        #expect(MCPPadAggregation.matches(pads[0], owner: "A@X.COM", state: nil, language: nil))
        #expect(MCPPadAggregation.matches(pads[0], owner: nil, state: "active", language: "PYTHON"))
        #expect(!MCPPadAggregation.matches(pads[0], owner: "b@x.com", state: nil, language: nil))
        #expect(MCPPadAggregation.matches(pads[0], owner: "", state: "", language: ""))
        #expect(!MCPPadAggregation.matches(pads[3], owner: "a@x.com", state: nil, language: nil))
    }

    @Test
    func `aggregateField normalizes synonyms and rejects unknown`() {
        #expect(MCPPadAggregation.aggregateField(for: "owner") == "owner_email")
        #expect(MCPPadAggregation.aggregateField(for: "Created_At") == "month")
        #expect(MCPPadAggregation.aggregateField(for: "bogus") == nil)
    }

    @Test
    func `counts bucket owners as stored and months by YYYY-MM, missing -> unknown`() {
        let owners = MCPPadAggregation.counts(pads: pads, field: "owner_email")
        #expect(owners["a@x.com"] == 1)
        #expect(owners["A@x.com"] == 1)
        #expect(owners["unknown"] == 1)

        let months = MCPPadAggregation.counts(pads: pads, field: "month")
        #expect(months["2026-01"] == 2)
        #expect(months["2026-02"] == 1)
        #expect(months["unknown"] == 1)
    }

    @Test
    func `topGroups sorts by count desc then key asc, and caps`() {
        let top = MCPPadAggregation.topGroups(["python": 5, "ruby": 5, "go": 3, "rust": 1], limit: 3)
        #expect(top == [
            MCPPadAggregation.Group(value: "python", count: 5),
            MCPPadAggregation.Group(value: "ruby", count: 5),
            MCPPadAggregation.Group(value: "go", count: 3)
        ])
    }

    @Test
    func `withinDateRange honors month, date and timestamp bounds, inclusively`() {
        let pad = pads[0] // created_at 2026-01-04T00:00:00Z
        // Absent/empty bounds always pass.
        #expect(MCPPadAggregation.withinDateRange(pad, after: nil, before: nil))
        #expect(MCPPadAggregation.withinDateRange(pad, after: "", before: ""))
        // Month-granularity bounds are inclusive.
        #expect(MCPPadAggregation.withinDateRange(pad, after: "2026-01", before: "2026-01"))
        #expect(!MCPPadAggregation.withinDateRange(pad, after: "2026-02", before: nil))
        #expect(!MCPPadAggregation.withinDateRange(pad, after: nil, before: "2025-12"))
        // Date-granularity bounds, inclusive on the day.
        #expect(MCPPadAggregation.withinDateRange(pad, after: "2026-01-04", before: "2026-01-04"))
        #expect(!MCPPadAggregation.withinDateRange(pad, after: "2026-01-05", before: nil))
        // A record with no created_at fails any present bound.
        #expect(!MCPPadAggregation.withinDateRange(pads[3], after: "2026-01", before: nil))
        #expect(MCPPadAggregation.withinDateRange(pads[3], after: nil, before: nil))
    }

    @Test
    func `compact keeps only the compact keys`() {
        let rich: [[String: Any]] = [[
            "id": "abc", "title": "T", "owner_email": "a@x.com", "state": "active",
            "language": "python", "created_at": "2026-01-01", "contents": "blob", "notes": "secret"
        ]]
        let compact = MCPPadAggregation.compact(rich)
        #expect(Set(compact[0].keys) == Set(MCPPadAggregation.compactKeys))
        #expect(compact[0]["contents"] == nil)
    }
}
