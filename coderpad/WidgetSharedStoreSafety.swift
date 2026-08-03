//
//  WidgetSharedStoreSafety.swift
//  coderpad
//

import Foundation
import OSLog

nonisolated extension WidgetSharedStore {
    static let maxSnapshotFileBytes = 1_048_576

    static func loadData(url: URL, purpose: String) -> Data? {
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  let size = values.fileSize,
                  (0 ... maxSnapshotFileBytes).contains(size) else {
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
