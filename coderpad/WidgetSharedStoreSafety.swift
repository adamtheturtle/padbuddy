//
//  WidgetSharedStoreSafety.swift
//  coderpad
//

import Foundation
import OSLog
#if canImport(Darwin)
    import Darwin
#else
    import Glibc
#endif

nonisolated extension WidgetSharedStore {
    static let maxSnapshotFileBytes = 1_048_576
    static let maxRequestFileBytes = 65536

    static func nextRequestOrdinal(now: UInt64, highest: UInt64) -> UInt64? {
        let (incremented, overflow) = highest.addingReportingOverflow(1)
        return overflow ? nil : max(now, incremented)
    }

    static func quarantineOverflowOrdinals(_ names: [String], in container: URL) {
        for name in names where requestOrdinal(fileName: name) == UInt64.max {
            let source = container.appending(path: name, directoryHint: .notDirectory)
            let destination = container.appending(
                path: "\(corruptRequestPrefix)overflow-\(UUID().uuidString).json",
                directoryHint: .notDirectory
            )
            try? FileManager.default.moveItem(at: source, to: destination)
        }
    }

    static func withPendingRequestLock<T>(_ body: () -> T) -> T? {
        guard let container = containerURL(purpose: pendingRequestsPurpose) else { return nil }

        let lockURL = container.appending(path: ".pending-request.lock", directoryHint: .notDirectory)
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return nil }

        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { return nil }

        defer { flock(descriptor, LOCK_UN) }
        return body()
    }

    static func loadData(url: URL, purpose: String) -> Data? {
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  let size = values.fileSize,
                  sharedStoreFileSizeIsAllowed(size, fileName: url.lastPathComponent)
            else {
                logger.error("Widget shared store refused an unsafe or oversized \(purpose, privacy: .public) file")
                return nil
            }

            return try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        } catch {
            logger.error("""
            Widget shared store read failed for \(purpose, privacy: .public): \
            \(error.localizedDescription, privacy: .private)
            """)
            return nil
        }
    }

    static func sharedStoreFileSizeIsAllowed(_ size: Int, fileName: String) -> Bool {
        guard size >= 0 else { return false }

        let isRequest = fileName.contains(newPadRequestPrefix) || fileName.contains(openPadRequestPrefix)
        return size <= (isRequest ? maxRequestFileBytes : maxSnapshotFileBytes)
    }
}
