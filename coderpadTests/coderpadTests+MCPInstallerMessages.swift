@testable import CoderPad
import Foundation
import MCPClientInstall
import Testing

#if os(macOS)
    @Suite("MCP installer error presentation")
    struct MCPInstallerMessageTests {
        @Test func `maps JSON compatibility errors to app copy`() {
            let error = MCPClientInstall.InstallWorkflowError.invalidConfiguration(
                url: URL(fileURLWithPath: "/tmp/mcp.json"),
                detail: "dependency detail"
            )

            let message = PadBuddyMCPInstaller.workflowMessage(error, fileName: "mcp.json")

            #expect(message.contains("mcpServers"))
            #expect(!message.contains("dependency detail"))
        }

        @Test func `maps TOML parser errors while retaining syntax detail`() {
            let error = MCPClientInstall.InstallWorkflowError.invalidConfiguration(
                url: URL(fileURLWithPath: "/tmp/config.toml"),
                detail: "line 2 has an unclosed string"
            )

            let message = PadBuddyMCPInstaller.workflowMessage(error, fileName: "config.toml")

            #expect(message.contains("line 2 has an unclosed string"))
            #expect(message.contains("Codex"))
        }
    }
#endif
