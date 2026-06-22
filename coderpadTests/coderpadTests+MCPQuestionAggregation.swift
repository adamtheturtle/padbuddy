//
//  coderpadTests+MCPQuestionAggregation.swift
//  coderpadTests
//
//  Tests for the in-app MCP server's QUESTION count/aggregate/compact transforms (#500):
//  filtering, grouping, ordering, and the compact projection over the question bank. Pure,
//  so tested without network.
//

@testable import CoderPad
import Foundation
import Testing

@Suite("MCP question aggregation")
struct MCPQuestionAggregationTests {
    private let questions: [[String: Any]] = [
        ["owner_email": "a@x.com", "author_name": "Ada", "language": "python",
         "pad_type": "sandbox", "created_at": "2026-01-04T00:00:00Z"],
        ["owner_email": "A@x.com", "author_name": "Ada", "language": "Python",
         "pad_type": "take_home", "created_at": "2026-01-20T00:00:00Z"],
        ["owner_email": "b@x.com", "author_name": "Bo", "language": "ruby",
         "pad_type": "sandbox", "created_at": "2026-02-02T00:00:00Z"],
        ["language": "ruby"]
    ]

    @Test
    func `matches filters by owner, author, language and type, case-insensitively`() {
        #expect(MCPQuestionAggregation.matches(questions[0], owner: "A@X.COM", author: nil, language: nil, type: nil))
        #expect(MCPQuestionAggregation.matches(questions[0], owner: nil, author: "ada", language: "PYTHON", type: nil))
        #expect(MCPQuestionAggregation.matches(questions[1], owner: nil, author: nil, language: nil, type: "TAKE_HOME"))
        #expect(!MCPQuestionAggregation.matches(questions[0], owner: nil, author: "Bo", language: nil, type: nil))
        #expect(!MCPQuestionAggregation.matches(
            questions[0], owner: nil, author: nil, language: nil, type: "take_home"
        ))
    }

    @Test
    func `matches treats empty and absent filters as wildcards`() {
        #expect(MCPQuestionAggregation.matches(questions[0], owner: "", author: "", language: "", type: ""))
        // A question missing owner_email/author_name still passes when those filters are absent.
        #expect(MCPQuestionAggregation.matches(questions[3], owner: nil, author: nil, language: "ruby", type: nil))
        // ...but fails a filter on a field it doesn't carry.
        #expect(!MCPQuestionAggregation.matches(questions[3], owner: "a@x.com", author: nil, language: nil, type: nil))
    }

    @Test
    func `aggregateField normalizes synonyms and rejects unknown`() {
        #expect(MCPQuestionAggregation.aggregateField(for: "owner") == "owner_email")
        #expect(MCPQuestionAggregation.aggregateField(for: "Author") == "author_name")
        #expect(MCPQuestionAggregation.aggregateField(for: "type") == "pad_type")
        #expect(MCPQuestionAggregation.aggregateField(for: "Created_At") == "month")
        #expect(MCPQuestionAggregation.aggregateField(for: "state") == nil)
    }

    @Test
    func `counts group by author and by month, missing -> unknown`() {
        let authors = MCPPadAggregation.counts(pads: questions, field: "author_name")
        #expect(authors["Ada"] == 2)
        #expect(authors["Bo"] == 1)
        #expect(authors["unknown"] == 1)

        let months = MCPPadAggregation.counts(pads: questions, field: "month")
        #expect(months["2026-01"] == 2)
        #expect(months["2026-02"] == 1)
        #expect(months["unknown"] == 1)
    }

    @Test
    func `filtersEcho includes only the set filters`() {
        let echo = MCPQuestionAggregation.filtersEcho(owner: "a@x.com", author: nil, language: "", type: "sandbox")
        #expect(echo["owner"] as? String == "a@x.com")
        #expect(echo["type"] as? String == "sandbox")
        #expect(echo["author"] == nil)
        #expect(echo["language"] == nil)
    }

    @Test
    func `compact keeps only the compact keys, dropping the verbose blob`() {
        let rich: [[String: Any]] = [[
            "id": 7, "title": "T", "owner_email": "a@x.com", "author_name": "Ada",
            "language": "python", "pad_type": "sandbox", "is_draft": false,
            "created_at": "2026-01-01", "solution": "secret", "contents": "blob"
        ]]
        let compact = MCPQuestionAggregation.compact(rich)
        #expect(Set(compact[0].keys) == Set(MCPQuestionAggregation.compactKeys))
        #expect(compact[0]["solution"] == nil)
        #expect(compact[0]["contents"] == nil)
    }
}
