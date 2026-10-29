//
//  WidgetSharedStoreSafety.swift
//  coderpad
//

import Darwin
import Foundation
import OSLog

nonisolated extension WidgetSharedStore {
    static let maxSnapshotFileBytes = 1_048_576

    static func loadData(url: URL, purpose: String, afterOpen: (() -> Void)? = nil) -> Data? {
        do {
            return try readBoundedRegularFile(at: url, afterOpen: afterOpen)
        } catch WidgetSharedStoreReadError.missing {
            return nil
        } catch WidgetSharedStoreReadError.unsafe {
            logger.error("Widget shared store refused an unsafe or oversized \(purpose, privacy: .public) file")
            return nil
        } catch {
            logger.error("""
            Widget shared store read failed for \(purpose, privacy: .public): \
            \(error.localizedDescription, privacy: .private)
            """)
            return nil
        }
    }

    static func readBoundedRegularFile(at url: URL, afterOpen: (() -> Void)?) throws -> Data {
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else {
            throw errno == ENOENT ? WidgetSharedStoreReadError.missing : .unavailable
        }

        defer { close(descriptor) }
        afterOpen?()

        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0 else {
            throw WidgetSharedStoreReadError.unavailable
        }
        guard metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_size >= 0,
              metadata.st_size <= maxSnapshotFileBytes else {
            throw WidgetSharedStoreReadError.unsafe
        }

        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags & ~O_NONBLOCK) == 0 else {
            throw WidgetSharedStoreReadError.unavailable
        }

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
                throw WidgetSharedStoreReadError.unavailable
            }
            guard count > 0 else { return data }
            guard data.count <= maxSnapshotFileBytes - count else {
                throw WidgetSharedStoreReadError.unsafe
            }

            data.append(buffer, count: count)
        }
    }
}

enum WidgetSharedStoreReadError: Error {
    case missing
    case unsafe
    case unavailable
}

nonisolated extension WidgetSharedStore {
    static func presentationText(_ raw: String, limit: Int) -> String {
        ExternalText.singleLine(raw, limit: limit)
    }

    static func plausibleTimestamp(_ date: Date?, now: Date = .now) -> Date? {
        guard let date, date.timeIntervalSince1970.isFinite, date.timeIntervalSince1970 >= 0,
              date <= now.addingTimeInterval(5 * 60) else { return nil }

        return date
    }
}
