//
//  WidgetSharedStoreSafety.swift
//  RecentPadsWidget
//

import Foundation
import OSLog

extension WidgetSharedStore {
    private static let maxSnapshotFileBytes = 1_048_576
    private static let maxRequestFileBytes = 65536

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

    static func loadData(at url: URL, purpose: String) -> Data? {
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  let size = values.fileSize,
                  size >= 0,
                  size <= (url.lastPathComponent.contains("pending-") ? maxRequestFileBytes : maxSnapshotFileBytes)
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
}
