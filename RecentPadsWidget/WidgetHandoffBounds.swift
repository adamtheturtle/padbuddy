//
//  WidgetHandoffBounds.swift
//  RecentPadsWidget
//

import Foundation
#if canImport(Darwin)
    import Darwin
#else
    import Glibc
#endif

extension WidgetSharedStore {
    private static var maxPendingRequests: Int {
        100
    }

    static func reservePendingRequestSlot() {
        guard let container = containerURL(purpose: "pending handoff requests"),
              let names = try? FileManager.default.contentsOfDirectory(atPath: container.path) else { return }

        let pending = names.filter {
            ($0.hasPrefix(newPadRequestPrefix) || $0.hasPrefix(openPadRequestPrefix))
                && $0.hasSuffix(requestFileExtension)
        }.sorted {
            let lhs = requestOrdinal(fileName: $0), rhs = requestOrdinal(fileName: $1)
            return lhs == rhs ? $0 < $1 : lhs < rhs
        }
        for name in pending.prefix(max(0, pending.count - (maxPendingRequests - 1))) {
            try? FileManager.default.removeItem(at: container.appending(path: name))
        }
    }

    static func withPendingRequestLock<T>(_ body: () -> T) -> T? {
        guard let container = containerURL(purpose: "pending handoff requests") else { return nil }

        let lockURL = container.appending(path: ".pending-request.lock", directoryHint: .notDirectory)
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return nil }

        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { return nil }

        defer { flock(descriptor, LOCK_UN) }
        return body()
    }
}
