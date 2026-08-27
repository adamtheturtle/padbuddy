//
//  PadBuddyTests+DateFilterClock.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Date filter clock")
struct DateFilterClockTests {
    private struct ClockFailure: Error {}

    @Test func `clock cancellation remains cancellation`() async {
        await #expect(throws: CancellationError.self) {
            try await DateFilterClock.wait { throw CancellationError() }
        }
    }

    @Test func `clock failure remains observable`() async {
        await #expect(throws: ClockFailure.self) {
            try await DateFilterClock.wait { throw ClockFailure() }
        }
    }
}
