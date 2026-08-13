//
//  PadBuddyTests+FocusScopeStackRestoration.swift
//  PadBuddyTests
//

import Foundation
import Testing
@testable import PadBuddy

@Suite("Focus scope stack restoration")
struct FocusScopeStackRestorationTests {
    private struct DecodeFailure: LocalizedError {
        var errorDescription: String? { "Damaged stack" }
    }

    @Test func `decode failure retains Focus restoration context`() {
        let outcome = FocusScopeStackRestoration.decode(
            Data(),
            expectedSessionID: "session",
            using: { _ in throw DecodeFailure() }
        )

        guard case let .failed(message) = outcome else {
            Issue.record("Expected Focus scope restoration failure")
            return
        }
        #expect(message == "Could not restore the Focus account scope stack: Damaged stack")
    }
}
