//
//  PadBuddyTests+PlaybackPositionStore.swift
//  PadBuddyTests
//

import Foundation
import Testing
@testable import PadBuddy

@Suite("Playback position persistence")
struct PlaybackPositionStoreTests {
    private struct EncodingFailure: Error {}

    @Test func `encoding failure preserves the previous saved positions`() throws {
        let suite = "PlaybackPositionStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let existing = try JSONEncoder().encode(["pad": Int64(42)])
        defaults.set(existing, forKey: PlaybackPositionStore.defaultsKey)

        let saved = PlaybackPositionStore.save(99, for: "pad", defaults: defaults) { _ in
            throw EncodingFailure()
        }

        #expect(!saved)
        #expect(defaults.data(forKey: PlaybackPositionStore.defaultsKey) == existing)
    }
}
