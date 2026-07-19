//
//  CodeSidebarWidth.swift
//  coderpad
//

import Foundation

enum CodeSidebarWidth {
    static let minimum = 120.0
    static let maximum = 420.0
    static let defaultValue = 180.0

    static func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return defaultValue }

        return min(max(minimum, value), maximum)
    }
}
