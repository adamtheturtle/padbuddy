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
        #expect(!MCPTools.hasAnyUpdatePadField([:]))
        #expect(object["title"] as? String == "")
        #expect(object["notes"] as? String == "")
        #expect(object["owner_email"] as? String == "")
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
        #expect(!MCPTools.hasAnyUpdateQuestionField([:]))
        #expect(object["title"] as? String == "")
        #expect(object["language"] as? String == "swift")
        #expect(object["description"] as? String == "")
        #expect(object["solution"] as? String == "")
        #expect(object["contents"] as? String == "")
    }
}
