//
//  PadBuddyTests+FavoriteQuestionCloudRemovalFailures.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Favorite question cloud removal failures")
struct FavoriteQuestionCloudRemovalFailureTests {
    private struct DecodeFailure: LocalizedError {
        var errorDescription: String? {
            "Damaged mirror"
        }
    }

    @Test func `decode failure retains cloud cleanup context`() {
        let result = FavoriteQuestionCloudRemoval.prepare(
            data: Data(),
            syncID: "removed",
            decode: { (_: Data) throws -> [String: [FavoriteQuestion]] in throw DecodeFailure() }
        )

        guard case let .failed(message) = result else {
            Issue.record("Expected cloud cleanup failure")
            return
        }

        #expect(message == "Could not decode favorite-question cloud data: Damaged mirror")
    }
}
