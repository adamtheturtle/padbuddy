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
    private func toolNames(allowWrites: Bool) -> [String] {
        MCPTools.all(allowWrites: allowWrites).compactMap { $0["name"] as? String }
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
        let tools = MCPTools.all(allowWrites: true)
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
}
