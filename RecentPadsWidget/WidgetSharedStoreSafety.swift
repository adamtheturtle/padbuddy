//
//  WidgetSharedStoreSafety.swift
//  RecentPadsWidget
//

import Darwin
import Foundation
import OSLog

extension WidgetSharedStore {
    private static let maxSnapshotFileBytes = 1_048_576

    static func loadData(at url: URL, purpose: String) -> Data? {
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else {
            if errno != ENOENT {
                logger.error("Widget shared store read failed for \(purpose, privacy: .public)")
            }
            return nil
        }

        defer { close(descriptor) }

        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_size >= 0,
              metadata.st_size <= maxSnapshotFileBytes else {
            logger.error("Widget shared store refused an unsafe or oversized \(purpose, privacy: .public) file")
            return nil
        }

        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags & ~O_NONBLOCK) == 0 else { return nil }

        var data = Data()
        data.reserveCapacity(Int(metadata.st_size))
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(descriptor, bytes.baseAddress, bytes.count)
            }
            guard count >= 0 else {
                if errno == EINTR {
                    continue
                }
                return nil
            }
            guard count > 0 else { return data }
            guard data.count <= maxSnapshotFileBytes - count else { return nil }

            data.append(buffer, count: count)
        }
    }
}
