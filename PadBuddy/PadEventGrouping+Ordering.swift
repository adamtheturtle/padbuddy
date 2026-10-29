//
//  PadEventGrouping+Ordering.swift
//  coderpad
//

import Foundation

extension PadEventGrouping {
    static func chronological(_ events: [PadEvent], now: Date = .now) -> [PadEvent] {
        let latestPlausibleDate = now.addingTimeInterval(5 * 60)
        return events.filter { event in
            guard let date = event.createdAt else { return true }

            return date.timeIntervalSince1970.isFinite && date <= latestPlausibleDate
        }.enumerated().sorted { lhs, rhs in
            let lhsDate = lhs.element.createdAt ?? .distantFuture
            let rhsDate = rhs.element.createdAt ?? .distantFuture
            return lhsDate == rhsDate ? lhs.offset < rhs.offset : lhsDate < rhsDate
        }.map(\.element)
    }
}
