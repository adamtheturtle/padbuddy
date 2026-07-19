//
//  coderpadTests+PadDateWindowValidation.swift
//  coderpadTests
//

import BuddyAppKit
@testable import CoderPad
import Foundation
import Testing

@Suite("Pad date-window validation")
struct PadDateWindowValidationTests {
    private let now = Date(timeIntervalSinceReferenceDate: 1_000_000)

    @Test
    func `unknown persisted date range fails closed`() {
        let invalid = DateWindow(range: "future migrated value")

        #expect(!PadDateWindowValidation.contains(invalid, date: now, now: now))
    }

    @Test
    func `custom start overrides an unknown named date range`() {
        let custom = DateWindow(
            range: "future migrated value",
            customStart: now.addingTimeInterval(-60)
        )

        #expect(PadDateWindowValidation.contains(custom, date: now, now: now))
    }
}
