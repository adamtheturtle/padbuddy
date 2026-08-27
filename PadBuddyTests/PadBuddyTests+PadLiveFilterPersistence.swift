//
//  PadBuddyTests+PadLiveFilterPersistence.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Pad live-filter persistence")
struct PadLiveFilterPersistenceTests {
    private struct EncodeFailure: LocalizedError {
        var errorDescription: String? {
            "Invalid filter value"
        }
    }

    @Test func `encoding failure preserves saved data and supplies contextual feedback`() {
        var saved = Data("previous".utf8)

        do {
            try PadLiveFilterPersistence.persist(
                "current",
                encode: { _ in throw EncodeFailure() },
                store: { saved = $0 }
            )
            Issue.record("Expected persistence to fail")
        } catch {
            #expect(saved == Data("previous".utf8))
            #expect(error.localizedDescription == "Could not save the current pad filters — Invalid filter value")
        }
    }
}
