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

    @Test func `decode failure invalidates malformed state and retains cleanup context`() {
        let result = FavoriteQuestionCloudRemoval.prepare(
            data: Data(),
            syncID: "removed",
            decode: { (_: Data) throws -> [String: [FavoriteQuestion]] in throw DecodeFailure() }
        )

        guard case let .invalidated(data, message) = result else {
            Issue.record("Expected explicit cloud invalidation")
            return
        }

        #expect(message == "Invalidated malformed account cloud data: Damaged mirror")
        #expect((try? JSONDecoder().decode([String: [FavoriteQuestion]].self, from: data))?.isEmpty == true)
    }
}
