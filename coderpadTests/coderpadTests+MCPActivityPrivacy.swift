//
//  coderpadTests+MCPActivityPrivacy.swift
//  coderpadTests
//

@testable import CoderPad
import Foundation
import Testing

@Suite("MCP activity privacy")
struct MCPActivityPrivacyTests {
    private let call = MCPActivityEntry(
        id: UUID(), time: Date(), kind: .call,
        tool: "get_sensitive_pad", account: "Private Account",
        succeeded: false, failureReason: "Sensitive failure"
    )

    @Test
    func `default presentation redacts activity identity and failure detail`() {
        #expect(MCPActivityPresentation.toolLabel(call, revealDetails: false) == "MCP tool call")
        #expect(MCPActivityPresentation.accountLabel(call, revealDetails: false) == nil)
        #expect(MCPActivityPresentation.failureReason(call, revealDetails: false) == nil)
    }

    @Test
    func `explicit reveal presents bounded activity details`() {
        #expect(MCPActivityPresentation.toolLabel(call, revealDetails: true) == "get_sensitive_pad")
        #expect(MCPActivityPresentation.accountLabel(call, revealDetails: true) == "Private Account")
        #expect(MCPActivityPresentation.failureReason(call, revealDetails: true) == "Sensitive failure")
    }

    @Test
    func `support export follows the activity details privacy preference`() throws {
        let redacted = try #require(String(data: MCPActivityExportDocument.exportData(
            entries: [call], revealDetails: false
        ), encoding: .utf8))
        let detailed = try #require(String(data: MCPActivityExportDocument.exportData(
            entries: [call], revealDetails: true
        ), encoding: .utf8))

        #expect(!redacted.contains("get_sensitive_pad"))
        #expect(!redacted.contains("Private Account"))
        #expect(!redacted.contains("Sensitive failure"))
        #expect(detailed.contains("get_sensitive_pad"))
        #expect(detailed.contains("Private Account"))
        #expect(detailed.contains("Sensitive failure"))
    }
}
