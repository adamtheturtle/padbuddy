@testable import BuddyAppKit
import Foundation
import os
import Testing

@Suite("Disk cache mutations")
struct DiskCacheMutationTests {
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
