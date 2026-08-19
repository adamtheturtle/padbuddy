//
//  PadBuddyTests+MCPActivityPrivacy.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing
#if canImport(Darwin)
    import Darwin
#endif

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
        let redacted = try #require(try String(data: MCPActivityExportDocument.exportData(
            entries: [call], revealDetails: false
        ), encoding: .utf8))
        let detailed = try #require(try String(data: MCPActivityExportDocument.exportData(
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
    func `support export encoding failure remains observable`() {
        #expect(throws: (any Error).self) {
            _ = try MCPActivityExportDocument.exportData(entries: [call], revealDetails: false) { _ in
                throw CocoaError(.fileWriteUnknown)
            }
        }
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
    func `invalid UTF-8 activity line is counted without blocking retention`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "activity.jsonl")
        try Data([0xFF]).write(to: file)

        let result = try #require(MCPActivityLog.loadDiagnostics(at: file))
        #expect(result.entries.isEmpty)
        #expect(result.unreadableLines == 1)
    }

    @Test
    func `oversized activity log reads only the retained tail`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "activity.jsonl")
        var payload = Data(repeating: 0x41, count: MCPActivityLog.maxReadBytes + 1)
        payload.append(0x0A)
        let encoder = JSONLLog<MCPActivityEntry>.iso8601Encoder
        for index in 0 ..< MCPActivityLog.maxEntries {
            let entry = MCPActivityEntry(
                id: UUID(), time: Date(), kind: .call, tool: "tool-\(index)",
                account: nil, succeeded: true, failureReason: nil
            )
            try payload.append(encoder.encode(entry))
            payload.append(0x0A)
        }
        try payload.write(to: file)

        let result = try #require(MCPActivityLog.loadDiagnostics(at: file))

        #expect(result.entries.count == MCPActivityLog.maxEntries)
        #expect(result.entries.first?.tool == "tool-0")
        #expect(result.entries.last?.tool == "tool-29")
        #expect(result.unreadableLines == 0)
    }

    @Test
    func `oversized single line is represented as unreadable without decoding it`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "activity.jsonl")
        try Data(repeating: 0x41, count: MCPActivityLog.maxReadBytes + 1).write(to: file)

        let result = try #require(MCPActivityLog.loadDiagnostics(at: file))

        #expect(result.entries.isEmpty)
        #expect(result.unreadableLines == 1)
    }

    @Test
    func `retention write failure is reported and preserves the old log`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JSONLLog<MCPActivityEntry>(
            directory: directory, fileName: "mcp-activity.jsonl", maxEntries: MCPActivityLog.maxEntries
        )
        let entry = MCPActivityEntry(
            id: UUID(), time: Date(), kind: .call, tool: "before", account: nil,
            succeeded: true, failureReason: nil
        )
        store.append(entry)
        let url = directory.appending(path: "mcp-activity.jsonl")
        let original = try Data(contentsOf: url)

        let succeeded = MCPActivityLog.trim(store: store) { _, _ in
            throw CocoaError(.fileWriteNoPermission)
        }

        #expect(!succeeded)
        #expect(try Data(contentsOf: url) == original)
        #expect(store.load().map(\.id) == [entry.id])
    }
}

@Suite("MCP activity lock safety")
struct MCPActivityLockSafetyTests {
    @Test
    func `FIFO lock path is rejected without blocking`() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let lock = directory.appending(path: "mcp-activity.jsonl.lock")
        #expect(mkfifo(lock.path, 0o600) == 0)

        let result = MCPActivityLog.withActivityLogLock(in: directory, exclusive: true) { true }

        #expect(result == nil)
    }

    @Test
    func `symbolic link lock path is rejected`() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appending(path: "target")
        let lock = directory.appending(path: "mcp-activity.jsonl.lock")
        try Data().write(to: target)
        try FileManager.default.createSymbolicLink(at: lock, withDestinationURL: target)

        let result = MCPActivityLog.withActivityLogLock(in: directory, exclusive: true) { true }

        #expect(result == nil)
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }
}
