//
//  PadBuddyTests+AccountAutosaveDebounce.swift
//  PadBuddyTests
//

import Foundation
import Testing
@testable import PadBuddy

@Suite("Account autosave debounce")
struct AccountAutosaveDebounceTests {
    private struct SchedulingFailure: LocalizedError {
        var errorDescription: String? { "Clock unavailable" }
    }

    @Test func `debounce cancellation remains cancellation`() async {
        await #expect(throws: CancellationError.self) {
            try await AccountAutosaveDebounce.wait { throw CancellationError() }
        }
    }

    @Test func `unexpected debounce failure has actionable UI context`() async throws {
        let error = try #require(await #expect(throws: SchedulingFailure.self) {
            try await AccountAutosaveDebounce.wait { throw SchedulingFailure() }
        })
        #expect(AccountAutosaveDebounce.failureMessage(for: error)
            == "Could not schedule the account autosave — Clock unavailable")
    }
}
