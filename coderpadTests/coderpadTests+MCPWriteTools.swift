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
    func `write permission is scoped to the selected account`() async throws {
        let baseURL = try #require(URL(string: "https://example.com"))
        let allowed = MCPCredentials(
            id: "allowed", apiKey: "key", baseURL: baseURL,
            accountName: "Allowed", userEmail: "allowed@example.com"
        )
        let denied = MCPCredentials(
            id: "denied", apiKey: "key", baseURL: baseURL,
            accountName: "Denied", userEmail: "denied@example.com"
        )
        let directory = MCPAccountDirectory(
            accounts: [allowed, denied],
            currentID: denied.id,
            writableAccountIDs: [allowed.id]
        )

        let outcome = await MCPTools.run(name: "create_pad", arguments: [:], directory: directory)
        #expect(outcome.isError)
        #expect(outcome.text.contains("selected CoderPad account"))
    }

    @Test
    func `pad seed validation rejects conflicting sources`() {
        #expect(padSeedValidationError(questionID: nil, contents: "print(1)") == nil)
        #expect(padSeedValidationError(questionID: 123, contents: nil) == nil)
        #expect(padSeedValidationError(questionID: 123, contents: "print(1)")?.contains("mutually exclusive") == true)
    }

    @Test
    func `malformed dry run values are rejected before a live write`() async throws {
        let baseURL = try #require(URL(string: "https://example.com"))
        let credentials = MCPCredentials(
            id: "writable", apiKey: "key", baseURL: baseURL,
            accountName: "Writable", userEmail: "writer@example.com"
        )
        let directory = MCPAccountDirectory(
            accounts: [credentials],
            currentID: credentials.id,
            writableAccountIDs: [credentials.id]
        )

        for value: Any in ["TRUE", "1", 1, 1.0] {
            let outcome = await MCPTools.run(
                name: "create_pad",
                arguments: ["dry_run": value],
                directory: directory
            )
            #expect(outcome.isError)
            #expect(outcome.text.contains("dry_run must be a boolean"))
        }
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
    func `successful writes invalidate the selected account cache`() async {
        let account = UUID()
        let kind = "pads"
        CacheDisk.save(["stale"], kind: kind, account: account)
        #expect(CacheDisk.load([String].self, kind: kind, account: account) == ["stale"])

        let success = await MCPTools.invalidateCache(
            kind: .pads,
            accountID: account.uuidString,
            after: MCPTools.Outcome(text: "OK", isError: false)
        )
        #expect(!success.isError)
        #expect(CacheDisk.load([String].self, kind: kind, account: account) == nil)
    }

    @Test
    func `failed writes keep the selected account cache`() async {
        let account = UUID()
        let kind = "pads"
        CacheDisk.save(["stale"], kind: kind, account: account)
        #expect(CacheDisk.load([String].self, kind: kind, account: account) == ["stale"])

        let failure = await MCPTools.invalidateCache(
            kind: .pads,
            accountID: account.uuidString,
            after: MCPTools.Outcome(text: "HTTP 500", isError: true)
        )
        #expect(failure.isError)
        #expect(CacheDisk.load([String].self, kind: kind, account: account) == ["stale"])
        CacheDisk.delete(kind: kind, account: account)
    }

    @Test @MainActor
    func `successful write clears only its in-memory list kind`() async throws {
        let account = Account(name: "MCP cache test", apiKey: "key-\(UUID().uuidString)")
        AccountsStore.shared.add(account)
        defer { AccountsStore.shared.remove(id: account.id) }
        let client = account.makeClient()
        let pad = Pad(id: "pad-\(UUID().uuidString)", title: "Stale")
        let questionData = try JSONSerialization.data(withJSONObject: ["id": 91827, "title": "Stale"])
        let question = try CoderPadClient.decoder.decode(Question.self, from: questionData)
        PadsCacheStore.shared.set(account.id, pads: [pad], via: client)
        QuestionsCacheStore.shared.set(account.id, questions: [question], via: client)
        let padGeneration = PadsCacheStore.shared.writeGeneration[account.id] ?? 0

        _ = await MCPTools.invalidateCache(
            kind: .pads,
            accountID: account.id.uuidString,
            after: MCPTools.Outcome(text: "OK", isError: false)
        )

        #expect(PadsCacheStore.shared.cached(account.id).isEmpty)
        #expect(QuestionsCacheStore.shared.cached(account.id) == [question])
        #expect(PadsCacheStore.shared.writeGeneration[account.id] == padGeneration + 1)
    }
}
