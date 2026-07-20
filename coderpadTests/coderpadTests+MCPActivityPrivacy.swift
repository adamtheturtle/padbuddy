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
}
