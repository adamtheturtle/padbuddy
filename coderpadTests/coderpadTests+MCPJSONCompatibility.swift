//
//  coderpadTests+MCPJSONCompatibility.swift
//  coderpadTests
//

@testable import CoderPad
import Testing

#if os(macOS)
    @Suite("JSON MCP existing-entry compatibility")
    struct MCPJSONCompatibilityTests {
        @Test
        func `malformed existing padbuddy entries are rejected without replacement`() {
            let entries: [Any] = [
                "legacy-value",
                ["unexpected", "array"],
                ["args": ["--legacy"]],
                ["command": "/old/PadBuddy", "args": "--mcp"]
            ]
            for entry in entries {
                let root: [String: Any] = ["mcpServers": ["padbuddy": entry]]
                #expect(throws: MCPClientInstall.JSONConfigError.self) {
                    try MCPClientInstall.jsonConfigByAddingServer(
                        to: root,
                        executablePath: "/Applications/PadBuddy"
                    )
                }
            }
        }

        @Test
        func `compatible existing padbuddy command can be updated`() throws {
            let root: [String: Any] = [
                "mcpServers": ["padbuddy": ["command": "/old/PadBuddy", "args": ["--mcp"]]]
            ]

            let merged = try MCPClientInstall.jsonConfigByAddingServer(
                to: root,
                executablePath: "/Applications/PadBuddy"
            )

            #expect(merged.alreadyPresent)
        }
    }
#endif
