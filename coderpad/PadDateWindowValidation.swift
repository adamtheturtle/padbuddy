//
//  PadDateWindowValidation.swift
//  coderpad
//

import BuddyAppKit
import Foundation

enum PadDateWindowValidation {
    /// A persisted named range that this version does not recognize is an active
    /// but invalid constraint, not an unconstrained window. Fail closed so corrupt
    /// or migrated filter state cannot silently broaden the result set (#2007).
    static func contains(_ window: DateWindow, date: Date, now: Date) -> Bool {
        if window.customStart == nil,
           let range = window.range,
           PadDateRange.start(for: range, now: now) == nil {
            return false
        }
        return window.contains(date, now: now)
    }
}
