//
//  coderpadTests+MCPWriteTools.swift
//  coderpadTests
//
//  Tests for the in-app MCP server's write opt-in (#502): the write tools must be hidden
//  from tools/list unless writing is enabled, and must be marked non-read-only so clients
//  can prompt. The descriptor list is pure, so it's checked directly.
//

@testable import CoderPad
import Foundation
import Testing

@Suite("MCP write tools opt-in")
struct MCPWriteToolsTests {
    private func toolNames(allowWrites: Bool, screenEnabled: Bool = false) -> [String] {
        MCPTools.all(allowWrites: allowWrites, screenEnabled: screenEnabled).compactMap { $0["name"] as? String }
    }

    private func encodedObject(_ value: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test
    func `write tools are hidden unless writing is enabled`() {
        let readOnly = toolNames(allowWrites: false)
        #expect(!readOnly.contains(where: { MCPTools.writeToolNames.contains($0) }))
        // The read tools are still there.
        #expect(readOnly.contains("list_pads"))
        #expect(readOnly.contains("get_pad"))
    }

    @Test
    func `enabling writes adds exactly the write tools`() {
        let readOnly = toolNames(allowWrites: false)
        let withWrites = toolNames(allowWrites: true)

        #expect(MCPTools.writeToolNames.allSatisfy { withWrites.contains($0) })
        #expect(withWrites.count == readOnly.count + MCPTools.writeToolNames.count)
        // Read tools are unaffected.
        #expect(Set(readOnly).isSubset(of: Set(withWrites)))
    }

    @Test
    func `write tools are annotated as not read-only`() {
        let tools = MCPTools.all(allowWrites: true, screenEnabled: false)
        for name in MCPTools.writeToolNames {
            let descriptor = tools.first { $0["name"] as? String == name }
            let annotations = descriptor?["annotations"] as? [String: Any]
            #expect(annotations?["readOnlyHint"] as? Bool == false,
                    "\(name) should be marked not read-only")
        }
    }

    @Test
    func `the write tool set is the four create/update tools`() {
        #expect(MCPTools.writeToolNames == ["create_pad", "update_pad", "create_question", "update_question"])
    }

    @Test
    func `pad seed validation rejects conflicting sources`() {
        #expect(padSeedValidationError(questionID: nil, contents: "print(1)") == nil)
        #expect(padSeedValidationError(questionID: 123, contents: nil) == nil)
        #expect(padSeedValidationError(questionID: 123, contents: "print(1)")?.contains("mutually exclusive") == true)
    }

    /// Non-positive question ids and whitespace-only contents are malformed
    /// seeds, not real ones (#1610, #1611).
    @Test
    func `pad seed validation rejects malformed seeds`() {
        #expect(padSeedValidationError(questionID: 0, contents: nil)?.contains("positive") == true)
        #expect(padSeedValidationError(questionID: -3, contents: nil)?.contains("positive") == true)
        #expect(padSeedValidationError(questionID: nil, contents: "   ")?.contains("whitespace") == true)
        #expect(padSeedValidationError(questionID: nil, contents: "")?.contains("whitespace") == true)
        #expect(padSeedValidationError(questionID: nil, contents: nil) == nil)
    }

    /// Pagination inputs have documented maximums, so an enormous page or
    /// offset can't stress the backend or overflow downstream arithmetic (#1612).
    @Test
    func `pagination validation enforces upper bounds`() {
        #expect(pageValidationError(maxPaginationPage) == nil)
        #expect(pageValidationError(maxPaginationPage + 1) != nil)
        #expect(screenPaginationValidationError(start: maxPaginationStart + 1, limit: nil) != nil)
        #expect(screenPaginationValidationError(start: nil, limit: maxPaginationLimit + 1) != nil)
        #expect(screenPaginationValidationError(start: 0, limit: maxPaginationLimit) == nil)
    }

    @Test
    func `screen tools appear only when Screen is enabled`() {
        let without = toolNames(allowWrites: false, screenEnabled: false)
        let with = toolNames(allowWrites: false, screenEnabled: true)

        #expect(!without.contains(where: { MCPTools.screenToolNames.contains($0) }))
        #expect(MCPTools.screenToolNames.allSatisfy { with.contains($0) })
        #expect(with.count == without.count + MCPTools.screenToolNames.count)
    }

    @Test
    func `the screen tool set is the three read-only screen tools`() {
        #expect(MCPTools.screenToolNames == ["screen_list_campaigns", "screen_list_tests", "screen_get_test"])
    }

    @Test
    func `update pad body preserves empty strings for clearing fields`() throws {
        let body = MCPTools.padUpdateBody(id: "pad-1", arguments: [
            "title": "",
            "notes": "",
            "owner_email": "",
            "language": "python3"
        ])
        let object = try encodedObject(body)

        #expect(MCPTools.hasAnyUpdatePadField(["notes": ""]))
        #expect(MCPTools.hasAnyUpdatePadField(["title": 42]))
        #expect(!MCPTools.hasAnyUpdatePadField(["title": true]))
        #expect(MCPTools.updatePadValidationError(["title": true])?.contains("title") == true)
        #expect(MCPTools.updatePadValidationError(["title": NSNull()])?.contains("string or integer") == true)
        #expect(MCPTools.updatePadValidationError(["title": ""]) == nil)
        #expect(!MCPTools.hasAnyUpdatePadField([:]))
        #expect((object["title"] as? String)?.isEmpty == true)
        #expect((object["notes"] as? String)?.isEmpty == true)
        #expect((object["owner_email"] as? String)?.isEmpty == true)
        #expect(object["language"] as? String == "python3")
    }

    @Test
    func `update question body preserves empty strings for clearing fields`() throws {
        let body = MCPTools.questionUpdateBody(id: 42, arguments: [
            "title": "",
            "language": "swift",
            "description": "",
            "solution": "",
            "contents": ""
        ])
        let object = try encodedObject(body)

        #expect(MCPTools.hasAnyUpdateQuestionField(["description": ""]))
        #expect(MCPTools.hasAnyUpdateQuestionField(["title": 42]))
        #expect(!MCPTools.hasAnyUpdateQuestionField(["solution": false]))
        #expect(MCPTools.updateQuestionValidationError(["solution": false])?.contains("solution") == true)
        #expect(MCPTools.updateQuestionValidationError(["contents": NSNull()])?.contains("string or integer") == true)
        #expect(MCPTools.updateQuestionValidationError(["description": ""]) == nil)
        #expect(!MCPTools.hasAnyUpdateQuestionField([:]))
        // CoderPadKit's QuestionUpdate nests title/language under a `question`
        // object, matching the API contract; the empty title must survive there.
        let question = try #require(object["question"] as? [String: Any])
        #expect((question["title"] as? String)?.isEmpty == true)
        #expect(question["language"] as? String == "swift")
        #expect((object["description"] as? String)?.isEmpty == true)
        #expect((object["solution"] as? String)?.isEmpty == true)
        #expect((object["contents"] as? String)?.isEmpty == true)
    }

    @Test
    func `required string trims and rejects blank input`() {
        #expect(MCPTools.requiredString(["title": "  Two Sum\n"], "title") == "Two Sum")
        #expect(MCPTools.requiredString(["title": "   \n"], "title") == nil)
        #expect(MCPTools.requiredString(["title": ""], "title") == nil)
        #expect(MCPTools.requiredString(["title": 42], "title") == "42")
    }

    @Test
    func `create question body uses normalized required title`() throws {
        let title = try #require(MCPTools.requiredString(["title": "  Two Sum\n"], "title"))
        let body = MCPTools.questionCreateBody(title: title, arguments: [
            "language": "swift",
            "description": "Prompt"
        ])
        let object = try encodedObject(body)
        let question = try #require(object["question"] as? [String: Any])

        #expect(question["title"] as? String == "Two Sum")
        #expect(question["language"] as? String == "swift")
        #expect(object["description"] as? String == "Prompt")
    }

    @Test
    func `successful writes invalidate the selected account cache`() {
        let account = UUID()
        let kind = "mcp-write-test-\(UUID().uuidString)"
        CacheDisk.save(["stale"], kind: kind, account: account)
        #expect(CacheDisk.load([String].self, kind: kind, account: account) == ["stale"])

        let success = MCPTools.invalidateCache(
            kind: kind,
            accountID: account.uuidString,
            after: MCPTools.Outcome(text: "OK", isError: false)
        )
        #expect(!success.isError)
        #expect(CacheDisk.load([String].self, kind: kind, account: account) == nil)
    }

    @Test
    func `failed writes keep the selected account cache`() {
        let account = UUID()
        let kind = "mcp-write-test-\(UUID().uuidString)"
        CacheDisk.save(["stale"], kind: kind, account: account)
        #expect(CacheDisk.load([String].self, kind: kind, account: account) == ["stale"])

        let failure = MCPTools.invalidateCache(
            kind: kind,
            accountID: account.uuidString,
            after: MCPTools.Outcome(text: "HTTP 500", isError: true)
        )
        #expect(failure.isError)
        #expect(CacheDisk.load([String].self, kind: kind, account: account) == ["stale"])
        CacheDisk.delete(kind: kind, account: account)
    }
}
