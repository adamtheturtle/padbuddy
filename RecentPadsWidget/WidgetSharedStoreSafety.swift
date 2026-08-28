//
//  WidgetSharedStoreSafety.swift
//  RecentPadsWidget
//

import Darwin
import Foundation
import OSLog

/// The outcome of reading one shared-container file.
///
/// `Data?` collapsed "the file is not there" and "the file is there but could not be
/// read" into `nil`, so the widget had to guess at unreadable access from an empty account
/// index — which is wrong in both directions: a user with genuinely no accounts was told
/// access was unavailable, and a truly unreadable container went unnoticed whenever the
/// index happened to decode (#4771).
enum WidgetDataLoad {
    case data(Data)
    case absent
    case unreadable
}

extension WidgetSharedStore {
    private static let maxSnapshotFileBytes = 1_048_576

    static func loadData(at url: URL, purpose: String) -> Data? {
        switch loadResult(at: url, purpose: purpose) {
        case let .data(data): data
        case .absent, .unreadable: nil
        }
    }

    static func loadResult(at url: URL, purpose: String) -> WidgetDataLoad {
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else {
            guard errno != ENOENT else { return .absent }

            logger.error("Widget shared store read failed for \(purpose, privacy: .public)")
            return .unreadable
        }

        defer { close(descriptor) }

        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_size >= 0,
              metadata.st_size <= maxSnapshotFileBytes else {
            logger.error("Widget shared store refused an unsafe or oversized \(purpose, privacy: .public) file")
            return .unreadable
        }

        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags & ~O_NONBLOCK) == 0 else { return .unreadable }

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
                return .unreadable
            }
            guard count > 0 else { return .data(data) }
            guard data.count <= maxSnapshotFileBytes - count else { return .unreadable }

            data.append(buffer, count: count)
        }
    }
}
