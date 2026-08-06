//
//  PadEventGrouping+Ordering.swift
//  coderpad
//

import Foundation

extension PadEventGrouping {
    static func chronological(_ events: [PadEvent]) -> [PadEvent] {
        events.enumerated().sorted { lhs, rhs in
            let lhsDate = lhs.element.createdAt ?? .distantFuture
            let rhsDate = rhs.element.createdAt ?? .distantFuture
            return lhsDate == rhsDate ? lhs.offset < rhs.offset : lhsDate < rhsDate
        }.map(\.element)
    }
}
