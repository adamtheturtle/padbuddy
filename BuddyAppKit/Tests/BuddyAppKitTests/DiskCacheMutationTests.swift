@testable import BuddyAppKit
import Foundation
import os
import Testing

@Suite("Disk cache mutations")
struct DiskCacheMutationTests {
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
