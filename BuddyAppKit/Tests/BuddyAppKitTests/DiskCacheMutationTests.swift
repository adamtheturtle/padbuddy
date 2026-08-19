@testable import BuddyAppKit
import Foundation
import os
import Testing

@Suite("Disk cache mutations")
struct DiskCacheMutationTests {
    @Test
    func `metadata distinguishes missing corrupt and unavailable snapshots`() throws {
        let account = UUID()
        let directoryName = "DiskCacheMutationTests-\(UUID().uuidString)"
        let base = try #require(FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first)
        let directory = base.appendingPathComponent(directoryName)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = DiskCache(directoryName: directoryName, logger: Logger(subsystem: "tests", category: "cache"))
        guard case .missing = cache.modificationDate(kind: "pads", account: account) else {
            Issue.record("An absent snapshot should be reported as missing")
            return
        }

        let file = directory.appendingPathComponent("pads-\(account.uuidString).json")
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: FileManager.default.temporaryDirectory)
        guard case .corrupt = cache.modificationDate(kind: "pads", account: account) else {
            Issue.record("An unsafe snapshot should be reported as corrupt")
            return
        }

        let invalid = DiskCache(directoryName: "../invalid", logger: Logger(subsystem: "tests", category: "cache"))
        guard case .unavailable = invalid.modificationDate(kind: "pads", account: account) else {
            Issue.record("Invalid cache configuration should be unavailable")
            return
        }
    }

    @Test
    func `intermediate directory symlink cannot escape cache root`() throws {
        let base = try #require(FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first)
        let component = "DiskCacheMutationTests-\(UUID().uuidString)"
        let link = base.appendingPathComponent(component)
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskCacheMutationTests-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: link)
            try? FileManager.default.removeItem(at: outside)
        }
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let account = UUID()
        let cache = DiskCache(
            directoryName: "\(component)/Data",
            logger: Logger(subsystem: "tests", category: "cache")
        )

        cache.save(["escaped"], kind: "pads", account: account)

        let escaped = outside.appendingPathComponent("Data/pads-\(account.uuidString).json")
        #expect(!FileManager.default.fileExists(atPath: escaped.path))
    }

    @Test
    func `distant future snapshot is quarantined`() throws {
        let account = UUID()
        let directoryName = "DiskCacheMutationTests-\(UUID().uuidString)"
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(directoryName, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = DiskCache(directoryName: directoryName, logger: Logger(subsystem: "tests", category: "cache"))
        cache.save(["old"], kind: "pads", account: account)
        let target = directory.appendingPathComponent("pads-\(account.uuidString).json")
        let now = Date()
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(24 * 60 * 60)],
            ofItemAtPath: target.path
        )

        guard case .corrupt = cache.loadResult(
            [String].self, kind: "pads", account: account, maximumAge: 60, now: now
        ) else {
            Issue.record("A distant-future timestamp must not be trusted")
            return
        }
        guard case .missing = cache.loadResult(
            [String].self, kind: "pads", account: account, maximumAge: 60, now: now
        ) else {
            Issue.record("The future-dated snapshot should be quarantined")
            return
        }
    }

    @Test
    func `oversized save does not replace the current snapshot`() {
        let account = UUID()
        let directoryName = "DiskCacheMutationTests-\(UUID().uuidString)"
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(directoryName, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let logger = Logger(subsystem: "tests", category: "cache")
        let initialCache = DiskCache(directoryName: directoryName, logger: logger)
        initialCache.save(["current"], kind: "pads", account: account)
        let boundedCache = DiskCache(directoryName: directoryName, logger: logger, maximumSnapshotBytes: 64)

        boundedCache.save([String(repeating: "x", count: 1024)], kind: "pads", account: account)

        #expect(initialCache.load([String].self, kind: "pads", account: account, maximumAge: 60) == ["current"])
    }

    @Test
    func `permission failure cannot remove another writer snapshot`() throws {
        let account = UUID()
        let directoryName = "DiskCacheMutationTests-\(UUID().uuidString)"
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(directoryName, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let logger = Logger(subsystem: "tests", category: "cache")
        let initialCache = DiskCache(directoryName: directoryName, logger: logger)
        initialCache.save(["concurrent"], kind: "pads", account: account)
        let target = directory.appendingPathComponent("pads-\(account.uuidString).json")
        let concurrentSnapshot = try Data(contentsOf: target)
        let failingCache = DiskCache(
            directoryName: directoryName,
            logger: logger,
            maximumSnapshotBytes: 1024,
            afterSnapshotRead: {},
            setSaveFilePermissions: { _ in
                try concurrentSnapshot.write(to: target, options: .atomic)
                throw CocoaError(.fileWriteNoPermission)
            }
        )

        failingCache.save(["failed"], kind: "pads", account: account)

        #expect(initialCache.load([String].self, kind: "pads", account: account, maximumAge: 60) == ["concurrent"])
    }

    @Test
    func `delete invalidates a save that began before it`() {
        let account = UUID()
        let directoryName = "DiskCacheMutationTests-\(UUID().uuidString)"
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(directoryName, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let saveReachedPublication = DispatchSemaphore(value: 0)
        let allowSaveToContinue = DispatchSemaphore(value: 0)
        let cache = DiskCache(
            directoryName: directoryName,
            logger: Logger(subsystem: "tests", category: "cache"),
            maximumSnapshotBytes: 1024,
            afterSnapshotRead: {},
            beforeSavePublish: {
                saveReachedPublication.signal()
                allowSaveToContinue.wait()
            }
        )
        let save = DispatchGroup()
        save.enter()
        DispatchQueue.global().async {
            cache.save(["late"], kind: "pads", account: account)
            save.leave()
        }
        saveReachedPublication.wait()

        #expect(cache.delete(kind: "pads", account: account))
        allowSaveToContinue.signal()
        save.wait()

        guard case .missing = cache.loadResult(
            [String].self, kind: "pads", account: account, maximumAge: 60
        ) else {
            Issue.record("A save begun before deletion must not recreate the snapshot")
            return
        }
    }
}
