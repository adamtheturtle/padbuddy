//
//  PadBuddyTests+SectionAvailabilitySettling.swift
//  PadBuddyTests
//

import Foundation
import Testing
@testable import PadBuddy

@Suite("Section availability settling")
struct SectionAvailabilitySettlingTests {
    private struct WaitFailure: Error {}

    @Test func `cancellation from settling remains cancellation`() async {
        await #expect(throws: CancellationError.self) {
            try await SectionAvailabilitySettling.wait { throw CancellationError() }
        }
    }

    @Test func `unexpected settling failure remains observable`() async {
        await #expect(throws: WaitFailure.self) {
            try await SectionAvailabilitySettling.wait { throw WaitFailure() }
        }
    }
}
