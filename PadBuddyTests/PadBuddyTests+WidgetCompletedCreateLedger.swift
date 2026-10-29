//
//  PadBuddyTests+WidgetCompletedCreateLedger.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Widget completed-create ledger")
struct WidgetCompletedCreateLedgerTests {
    private func container() throws -> URL {
        let url = URL.temporaryDirectory.appending(
            path: "ledger-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test(arguments: [false, true])
    func `ledger and lock symlinks make the replay gate unavailable`(_ lockFile: Bool) throws {
        let directory = try container()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("target.json")
        let original = Data("{}".utf8)
        try original.write(to: target)
        let name = WidgetCompletedCreateLedger.fileName + (lockFile ? ".lock" : "")
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent(name), withDestinationURL: target
        )
        #expect(WidgetCompletedCreateLedger.claim(UUID(), containerURL: directory) == .unavailable)
        #expect(try Data(contentsOf: target) == original)
    }

    @Test(arguments: [false, true])
    func `oversized ledger bytes and entry counts refuse replay claims`(_ tooManyEntries: Bool) throws {
        let directory = try container()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent(WidgetCompletedCreateLedger.fileName)
        let data: Data
        if tooManyEntries {
            let entries = Dictionary(uniqueKeysWithValues: (0 ... WidgetCompletedCreateLedger.maximumEntries).map { _ in
                (UUID().uuidString, WidgetCompletedCreateLedger.Entry(state: .completed, recordedAt: 0))
            })
            data = try JSONEncoder().encode(entries)
        } else {
            data = Data(repeating: 0x20, count: WidgetSharedStore.maxSnapshotFileBytes + 1)
        }
        try data.write(to: url)
        #expect(WidgetCompletedCreateLedger.claim(UUID(), containerURL: directory) == .unavailable)
        #expect(try Data(contentsOf: url) == data)
    }

    @Test func `a completed request is not created again`() throws {
        let directory = try container()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID()
        #expect(WidgetCompletedCreateLedger.claim(id, containerURL: directory) == .proceed)

        try WidgetCompletedCreateLedger.recordCompleted(id, containerURL: directory)

        #expect(WidgetCompletedCreateLedger.claim(id, containerURL: directory) == .alreadyCompleted)
    }

    @Test func `a present but unreadable ledger makes the replay gate unavailable`() throws {
        let directory = try container()
        defer { try? FileManager.default.removeItem(at: directory) }
        let ledger = directory.appending(
            path: WidgetCompletedCreateLedger.fileName,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: ledger, withIntermediateDirectories: false)

        #expect(WidgetCompletedCreateLedger.claim(UUID(), containerURL: directory) == .unavailable)
        #expect(FileManager.default.fileExists(atPath: ledger.path))
    }

    @Test func `a live claim blocks a second drain from creating`() throws {
        let directory = try container()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID()

        #expect(WidgetCompletedCreateLedger.claim(id, containerURL: directory) == .proceed)

        // The gap the old read-then-write gate left open: both drains saw the id absent.
        #expect(WidgetCompletedCreateLedger.claim(id, containerURL: directory) == .inProgressElsewhere)
    }

    @Test func `an abandoned claim is recovered after its lifetime`() throws {
        let directory = try container()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID()
        #expect(WidgetCompletedCreateLedger.claim(id, containerURL: directory) == .proceed)

        let later = Date().addingTimeInterval(WidgetCompletedCreateLedger.abandonedClaimLifetime + 1)

        #expect(WidgetCompletedCreateLedger.claim(id, now: later, containerURL: directory) == .proceed)
    }

    @Test func `releasing a claim lets the request be retried at once`() throws {
        let directory = try container()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID()
        #expect(WidgetCompletedCreateLedger.claim(id, containerURL: directory) == .proceed)

        WidgetCompletedCreateLedger.releaseClaim(id, containerURL: directory)

        #expect(WidgetCompletedCreateLedger.claim(id, containerURL: directory) == .proceed)
    }

    @Test func `releasing does not undo a recorded completion`() throws {
        let directory = try container()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID()
        _ = WidgetCompletedCreateLedger.claim(id, containerURL: directory)
        try WidgetCompletedCreateLedger.recordCompleted(id, containerURL: directory)

        WidgetCompletedCreateLedger.releaseClaim(id, containerURL: directory)

        #expect(WidgetCompletedCreateLedger.claim(id, containerURL: directory) == .alreadyCompleted)
    }

    @Test func `distinct request identities remain independent`() throws {
        let directory = try container()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = UUID()
        let second = UUID()

        _ = WidgetCompletedCreateLedger.claim(first, containerURL: directory)
        try WidgetCompletedCreateLedger.recordCompleted(first, containerURL: directory)

        #expect(WidgetCompletedCreateLedger.claim(first, containerURL: directory) == .alreadyCompleted)
        #expect(WidgetCompletedCreateLedger.claim(second, containerURL: directory) == .proceed)
    }

    @Test func `a completion survives long past the old 512-entry ring`() throws {
        let directory = try container()
        defer { try? FileManager.default.removeItem(at: directory) }
        let old = UUID()
        _ = WidgetCompletedCreateLedger.claim(old, containerURL: directory)
        try WidgetCompletedCreateLedger.recordCompleted(old, containerURL: directory)

        // The ring used to drop this after 512 newer completions, making a request that
        // was still recoverable from the transport replayable (#4550).
        for _ in 0 ..< 600 {
            let id = UUID()
            _ = WidgetCompletedCreateLedger.claim(id, containerURL: directory)
            try WidgetCompletedCreateLedger.recordCompleted(id, containerURL: directory)
        }

        #expect(WidgetCompletedCreateLedger.claim(old, containerURL: directory) == .alreadyCompleted)
    }

    @Test func `entries older than the retention window are pruned`() throws {
        let directory = try container()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID()
        _ = WidgetCompletedCreateLedger.claim(id, containerURL: directory)
        try WidgetCompletedCreateLedger.recordCompleted(id, containerURL: directory)

        let later = Date().addingTimeInterval(WidgetCompletedCreateLedger.retentionLifetime + 60)
        // Any write prunes; use an unrelated id so the pruning is what clears the old one.
        _ = WidgetCompletedCreateLedger.claim(UUID(), now: later, containerURL: directory)

        #expect(WidgetCompletedCreateLedger.entries(in: directory)[id.uuidString] == nil)
    }
}
