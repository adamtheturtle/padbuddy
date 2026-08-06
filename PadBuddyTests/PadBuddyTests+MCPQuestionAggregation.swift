//
//  PadBuddyTests+MCPQuestionAggregation.swift
//  PadBuddyTests
//
//  Tests for the in-app MCP server's QUESTION count/aggregate/compact transforms (#500):
//  filtering, grouping, ordering, and the compact projection over the question bank. Pure,
//  so tested without network.
//

@testable import PadBuddy
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
        #expect(questionMatches(questions[0], owner: "A@X.COM", author: nil, language: nil, type: nil))
        #expect(questionMatches(questions[0], owner: nil, author: "ada", language: "PYTHON", type: nil))
        #expect(questionMatches(questions[1], owner: nil, author: nil, language: nil, type: "TAKE_HOME"))
        #expect(!questionMatches(questions[0], owner: nil, author: "Bo", language: nil, type: nil))
        #expect(!questionMatches(
            questions[0], owner: nil, author: nil, language: nil, type: "take_home"
        ))
    }

    /// Interview-type spellings fold to one canonical token, so the tool value
    /// `take-home` matches the API's `take_home` and vice versa (#1609).
    @Test
    func `type filter folds interview-type spellings`() {
        #expect(questionMatches(questions[1], owner: nil, author: nil, language: nil, type: "take-home"))
        #expect(questionMatches(questions[1], owner: nil, author: nil, language: nil, type: "takehome"))
        #expect(questionMatches(questions[1], owner: nil, author: nil, language: nil, type: " take_home "))
        #expect(!questionMatches(questions[0], owner: nil, author: nil, language: nil, type: "take-home"))
    }

    @Test
    func `matches treats empty and absent filters as wildcards`() {
        #expect(questionMatches(questions[0], owner: "", author: "", language: "", type: ""))
        // A question missing owner_email/author_name still passes when those filters are absent.
        #expect(questionMatches(questions[3], owner: nil, author: nil, language: "ruby", type: nil))
        // ...but fails a filter on a field it doesn't carry.
        #expect(!questionMatches(questions[3], owner: "a@x.com", author: nil, language: nil, type: nil))
    }

    @Test
    func `aggregateField normalizes synonyms and rejects unknown`() {
        #expect(questionAggregateField(for: "owner") == "owner_email")
        #expect(questionAggregateField(for: "Author") == "author_name")
        #expect(questionAggregateField(for: "type") == "pad_type")
        #expect(questionAggregateField(for: "Created_At") == "month")
        #expect(questionAggregateField(for: "state") == nil)
    }

    @Test
    func `counts canonicalize authors and use the shared missing bucket`() {
        let authors = aggregateCounts(pads: questions, field: "author_name")
        #expect(authors["ada"] == 2)
        #expect(authors["bo"] == 1)
        #expect(authors[aggregateMissingGroup] == 1)

        let months = aggregateCounts(pads: questions, field: "month")
        #expect(months["2026-01"] == 2)
        #expect(months["2026-02"] == 1)
        #expect(months[aggregateMissingGroup] == 1)
    }

    @Test
    func `filtersEcho includes only the set filters`() {
        let echo = questionFiltersEcho(owner: "a@x.com", author: nil, language: "", type: "sandbox")
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
        let compact = compactQuestions(rich)
        #expect(Set(compact[0].keys) == Set(compactQuestionKeys))
        #expect(compact[0]["solution"] == nil)
        #expect(compact[0]["contents"] == nil)
    }
}
