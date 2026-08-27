//
//  PadBuddyTests+DateRangeLabel.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Custom date-range label")
@MainActor
struct CustomDateRangeLabelTests {
    @Test
    func `endpoints include their years`() throws {
        let start = try #require(ISO8601DateFormatter().date(from: "2025-12-31T12:00:00Z"))
        let end = try #require(ISO8601DateFormatter().date(from: "2026-01-01T12:00:00Z"))

        let label = DateRangeFilterChip.customRangeLabel(start: start, end: end)

        #expect(label.contains("2025"))
        #expect(label.contains("2026"))
    }
}
