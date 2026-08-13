//
//  PadBuddyTests+MergedQuestionFilterRestoration.swift
//  PadBuddyTests
//

import Foundation
import Testing
@testable import PadBuddy

@Suite("Merged question filter restoration")
struct MergedQuestionFilterRestorationTests {
    private struct DecodeFailure: LocalizedError {
        let errorDescription: String?
    }

    @Test func `both decoding failures retain operation context`() {
        let result = MergedQuestionFilterRestoration.decode(
            Data(),
            snapshot: { _ in throw DecodeFailure(errorDescription: "Bad snapshot") },
            legacy: { _ in throw DecodeFailure(errorDescription: "Bad legacy search") }
        )

        guard case let .invalid(detail) = result else {
            Issue.record("Expected invalid persisted filters")
            return
        }
        #expect(detail == "Snapshot decode failed: Bad snapshot; legacy decode failed: Bad legacy search")
    }
}
