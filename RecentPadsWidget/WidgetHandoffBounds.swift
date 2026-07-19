//
//  WidgetHandoffBounds.swift
//  RecentPadsWidget
//

import Foundation

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
}
