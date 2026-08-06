@testable import PadBuddy
import Foundation
import Testing

@Suite("Organization stats windows")
struct OrganizationStatsWindowTests {
    private let calendar = Calendar(identifier: .gregorian)

    @Test func `custom windows end no later than now`() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let range = StatsPeriod.boundedCustomRange(
            start: now.addingTimeInterval(-60),
            end: now.addingTimeInterval(60),
            now: now,
            calendar: calendar
        )

        #expect(range.end == now)
        #expect(range.start == now.addingTimeInterval(-60))
    }

    @Test func `custom windows are limited to twelve months`() throws {
        let end = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 19)))
        let earliest = try #require(calendar.date(byAdding: .month, value: -12, to: end))
        let range = StatsPeriod.boundedCustomRange(
            start: Date.distantPast,
            end: end,
            now: end,
            calendar: calendar
        )

        #expect(range == (earliest, end))
    }

    @Test func `inverted custom windows collapse safely`() {
        let end = Date(timeIntervalSince1970: 2_000_000)
        let range = StatsPeriod.boundedCustomRange(
            start: end.addingTimeInterval(60),
            end: end,
            now: end,
            calendar: calendar
        )

        #expect(range.start == end)
        #expect(range.end == end)
    }
}
