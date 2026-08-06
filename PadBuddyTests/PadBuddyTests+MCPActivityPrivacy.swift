//
//  PadBuddyTests+MCPActivityPrivacy.swift
//  PadBuddyTests
//

@testable import PadBuddy
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

    @Test
    func `activity can be filtered by visible tool or account without hidden-field disclosure`() {
        #expect(MCPActivityPresentation.filteredCalls(
            [call], query: "SENSITIVE", revealDetails: true
        ) == [call])
        #expect(MCPActivityPresentation.filteredCalls(
            [call], query: "private account", revealDetails: true
        ) == [call])
        #expect(MCPActivityPresentation.filteredCalls(
            [call], query: "no match", revealDetails: true
        ).isEmpty)
        #expect(MCPActivityPresentation.filteredCalls(
            [call], query: "sensitive", revealDetails: false
        ) == [call])
    }

    @Test
    func `failure summary skips whitespace-only lines`() {
        #expect(MCPActivityLog.sanitizedReason("  \t \nActual failure") == "Actual failure")
        #expect(MCPActivityLog.sanitizedReason(" \n\t\n  ") == nil)
    }

    @Test
    func `failure summary strips controls and format scalars`() {
        #expect(MCPActivityLog.sanitizedReason("bad\t\u{1B}\u{202E}reason\rtext") == "badreasontext")
        #expect(MCPActivityLog.sanitizedReason("\u{202E}\u{200B}") == nil)
    }
}

@Suite("MCP activity diagnostics")
struct MCPActivityDiagnosticsTests {
    @Test
    func `missing activity file is a readable empty log`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let result = try #require(MCPActivityLog.loadDiagnostics(
            at: directory.appending(path: "missing.jsonl")
        ))

        #expect(result.entries.isEmpty)
        #expect(result.unreadableLines == 0)
    }

    @Test
    func `invalid UTF-8 activity file is unreadable`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "activity.jsonl")
        try Data([0xFF]).write(to: file)

        #expect(MCPActivityLog.loadDiagnostics(at: file) == nil)
    }
}
