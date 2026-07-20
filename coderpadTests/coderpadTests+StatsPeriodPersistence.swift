@testable import CoderPad
import Foundation
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
}
