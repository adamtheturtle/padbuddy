//
//  PadBuddyTests+QuotaTrialClock.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Quota trial clock")
struct QuotaTrialClockTests {
    @Test func `waits exactly until a future trial expires`() async throws {
        let now = Date(timeIntervalSince1970: 1000)
        var delay: Duration?

        try await QuotaTrialClock.waitUntilExpiration(
            now.addingTimeInterval(90), now: now,
            sleep: { delay = $0 }
        )

        #expect(delay == .seconds(90))
    }

    @Test func `an expired trial does not schedule a wait`() async throws {
        let now = Date(timeIntervalSince1970: 1000)
        var didSleep = false

        try await QuotaTrialClock.waitUntilExpiration(
            now.addingTimeInterval(-1), now: now,
            sleep: { _ in didSleep = true }
        )

        #expect(!didSleep)
    }
}
