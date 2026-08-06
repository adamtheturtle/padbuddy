//
//  PadBuddyTests+MCPHealthCheck.swift
//  PadBuddyTests
//

@testable import PadBuddy
import Testing

#if os(macOS)
    @Suite("MCP health check")
    struct MCPHealthCheckTests {
        @Test
        func `disabled server is not reported usable`() {
            let result = MCPHealthCheck.evaluate(enabled: false, usableAccountCount: 1)
            #expect(!result.isUsable)
            #expect(result.output.contains("disabled"))
        }

        @Test
        func `enabled server requires a usable saved account`() {
            #expect(!MCPHealthCheck.evaluate(enabled: true, usableAccountCount: 0).isUsable)
            #expect(MCPHealthCheck.evaluate(enabled: true, usableAccountCount: 1).isUsable)
        }

        @Test @MainActor
        func `copyable diagnostic includes environment and failure`() {
            let diagnostic = SettingsView.mcpHealthDiagnostic(message: "Self-test timed out")

            #expect(diagnostic.contains("PadBuddy MCP health diagnostic"))
            #expect(diagnostic.contains("Platform:"))
            #expect(diagnostic.contains("Executable:"))
            #expect(diagnostic.contains("Self-test timed out"))
        }
    }
#endif
