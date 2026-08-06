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

    /// Applies the persisted preference within one rendering surface while
    /// reserving useful horizontal space for code. The preference itself remains
    /// unchanged, so reopening in a wider window restores the user's chosen width.
    static func effective(_ stored: Double, availableWidth: Double, minimumCodeWidth: Double = 220) -> Double {
        let preferred = clamped(stored)
        guard availableWidth.isFinite, availableWidth > 0,
              minimumCodeWidth.isFinite, minimumCodeWidth >= 0 else { return preferred }

        return min(preferred, max(minimum, availableWidth - minimumCodeWidth))
    }
}
