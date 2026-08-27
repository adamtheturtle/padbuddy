//
//  PadBuddyTests+FavoriteDragEncoding.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Favorite drag encoding")
struct FavoriteDragEncodingTests {
    private struct EncodeFailure: LocalizedError {
        var errorDescription: String? {
            "Unsupported title"
        }
    }

    @Test func `encoding failures retain operation context`() {
        let drop = FavoriteDrop.question(account: UUID(), id: 42, title: "Question")

        do {
            _ = try encodedFavoriteDrop(drop, using: { _ in throw EncodeFailure() })
            Issue.record("Expected drag encoding to fail")
        } catch {
            #expect(error.localizedDescription
                == "Could not encode the internal favorite drag payload: Unsupported title")
        }
    }
}
