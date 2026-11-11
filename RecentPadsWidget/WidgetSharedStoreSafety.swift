//
//  WidgetSharedStoreSafety.swift
//  RecentPadsWidget
//

import Darwin
import Foundation
import os

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
    static func validatedNewPadRequest(
        account: String?, question: Int?, requestID: UUID = UUID()
    ) -> WidgetNewPadRequest? {
        guard question == nil || question.map({ $0 > 0 }) == true,
              let owner = validatedAccount(account), owner != nil || question == nil else { return nil }

        return WidgetNewPadRequest(account: owner, question: question, id: requestID)
    }

    private static let maxSnapshotFileBytes = 1_048_576

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

extension WidgetSharedStore {
    static func presentationText(_ raw: String, limit: Int) -> String {
        guard limit > 0 else { return "" }

        var output = "", pendingSpace = false
        for scalar in raw.unicodeScalars.prefix(limit) {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                pendingSpace = true
                continue
            }
            switch scalar.properties.generalCategory {
            case .control, .format, .privateUse, .surrogate, .unassigned:
                continue
            default:
                break
            }
            if pendingSpace, !output.isEmpty {
                output.append(" ")
            }
            output.unicodeScalars.append(scalar)
            pendingSpace = false
        }
        return output
    }

    static func plausibleTimestamp(_ date: Date?, now: Date = .now) -> Date? {
        guard let date, date.timeIntervalSince1970.isFinite, date.timeIntervalSince1970 >= 0,
              date <= now.addingTimeInterval(5 * 60) else { return nil }

        return date
    }
}
