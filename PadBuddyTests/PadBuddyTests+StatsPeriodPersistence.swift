import Foundation
@testable import PadBuddy
import Testing

@Suite("Stats period persistence", .serialized)
struct StatsPeriodPersistenceTests {
    @Test
    func `custom ranges persist independently by scope and are validated`() throws {
        let suite = "StatsPeriodPersistenceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let accountStart = now.addingTimeInterval(-86400 * 30)

        StatsPeriod.persistCustomRange(
            start: accountStart, end: now.addingTimeInterval(86400),
            scope: "account.a", defaults: defaults, now: now
        )

        let account = StatsPeriod.persistedCustomRange(scope: "account.a", defaults: defaults, now: now)
        let merged = StatsPeriod.persistedCustomRange(scope: "merged", defaults: defaults, now: now)
        #expect(account.start == accountStart)
        #expect(account.end == now)
        #expect(merged.start != account.start)
    }

    @Test(arguments: [Double.nan, Double.infinity, -Double.infinity])
    func `nonfinite timestamps reset to the documented fallback`(invalid: Double) throws {
        let suite = "StatsPeriodPersistenceTests.invalid.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let expectedStart = try #require(Calendar.current.date(byAdding: .day, value: -7, to: now))
        let startKey = "organization.customRange.invalid.start"
        let endKey = "organization.customRange.invalid.end"
        defaults.set(invalid, forKey: startKey)
        defaults.set(now.timeIntervalSince1970, forKey: endKey)

        let range = StatsPeriod.persistedCustomRange(scope: "invalid", defaults: defaults, now: now)

        #expect(range == (expectedStart, now))
        #expect(defaults.double(forKey: startKey) == expectedStart.timeIntervalSince1970)
        #expect(defaults.double(forKey: endKey) == now.timeIntervalSince1970)
    }
}
