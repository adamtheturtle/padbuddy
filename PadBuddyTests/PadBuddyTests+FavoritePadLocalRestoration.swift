//
//  PadBuddyTests+FavoritePadLocalRestoration.swift
//  PadBuddyTests
//

import Foundation
import Testing
@testable import PadBuddy

@Suite("Favorite pad local restoration")
struct FavoritePadLocalRestorationTests {
    private struct DecodeFailure: LocalizedError {
        var errorDescription: String? { "Corrupt property list" }
    }

    @Test func `decode failure retains the affected store context`() {
        do {
            let _: [UUID: [FavoritePad]] = try FavoritePadLocalRestoration.decode(
                Data(),
                context: "favorite pad membership",
                using: { _ in throw DecodeFailure() }
            )
            Issue.record("Expected restoration to fail")
        } catch {
            #expect(error.localizedDescription
                == "Could not restore favorite pad membership: Corrupt property list")
        }
    }
}
