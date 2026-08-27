//
//  PadBuddyTests+PlaybackPositionStore.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Playback position persistence")
struct PlaybackPositionStoreTests {
    private struct EncodingFailure: Error {}

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suite = "PlaybackPositionStoreTests.\(UUID().uuidString)"
        return try (#require(UserDefaults(suiteName: suite)), suite)
    }

    @Test func `encoding failure preserves the previous saved positions`() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let existing = try JSONEncoder().encode(
            ["pad": PlaybackPositionStore.Entry(timestamp: 42, savedAt: 0)]
        )
        defaults.set(existing, forKey: PlaybackPositionStore.defaultsKey)

        let saved = PlaybackPositionStore.save(99, for: "pad", defaults: defaults) { _ in
            throw EncodingFailure()
        }

        #expect(!saved)
        #expect(defaults.data(forKey: PlaybackPositionStore.defaultsKey) == existing)
    }

    @Test func `history IDs containing the separator do not share a key`() {
        let separated = PlaybackPositionStore.key(for: [history(id: "a\u{1F}b")])
        let split = PlaybackPositionStore.key(for: [history(id: "a"), history(id: "b")])

        #expect(separated != split)
        #expect(!separated.isEmpty)
    }

    @Test func `key is stable regardless of the order histories arrive in`() {
        let forwards = PlaybackPositionStore.key(for: [history(id: "a"), history(id: "b")])
        let backwards = PlaybackPositionStore.key(for: [history(id: "b"), history(id: "a")])

        #expect(forwards == backwards)
    }

    @Test func `an empty history set has no key`() {
        #expect(PlaybackPositionStore.key(for: []).isEmpty)
    }

    @Test func `a nil timestamp removes the stale saved position`() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(PlaybackPositionStore.save(42, for: "pad", defaults: defaults))

        #expect(PlaybackPositionStore.save(nil, for: "pad", defaults: defaults))

        #expect(PlaybackPositionStore.timestamp(for: "pad", defaults: defaults) == nil)
    }

    @Test func `removing a position that was never saved writes nothing`() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(!PlaybackPositionStore.save(nil, for: "absent", defaults: defaults))

        #expect(defaults.data(forKey: PlaybackPositionStore.defaultsKey) == nil)
    }

    @Test func `saved positions are bounded and evict the least recently used`() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        for index in 0 ... PlaybackPositionStore.entryLimit {
            #expect(PlaybackPositionStore.save(
                Int64(index), for: "key-\(index)", now: Double(index), defaults: defaults
            ))
        }

        // The oldest save is the one evicted; the newest is always kept.
        #expect(PlaybackPositionStore.timestamp(for: "key-0", defaults: defaults) == nil)
        let newest = "key-\(PlaybackPositionStore.entryLimit)"
        #expect(PlaybackPositionStore.timestamp(for: newest, defaults: defaults)
            == Int64(PlaybackPositionStore.entryLimit))
    }

    @Test func `the unreadable v1 blob is cleared rather than left in defaults`() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        try defaults.set(JSONEncoder().encode(["pad": Int64(42)]), forKey: "padHistoryPlaybackPositions")

        _ = PlaybackPositionStore.timestamp(for: "pad", defaults: defaults)

        #expect(defaults.object(forKey: "padHistoryPlaybackPositions") == nil)
    }

    private func history(id: String) -> PadFileHistory {
        PadFileHistory(id: id, title: id, language: nil, history: PadHistory(entries: []))
    }
}
