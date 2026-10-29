//
//  PlaybackPositionStore.swift
//  coderpad
//

import CryptoKit
import Foundation
import os
import SwiftUI

nonisolated enum PlaybackPositionStore {
    /// A saved entry: the revision timestamp the user left off at, plus when that was
    /// recorded so the store can evict the least recently used sets (#4543).
    struct Entry: Codable, Hashable {
        let timestamp: Int64
        let savedAt: Double
    }

    /// v2 stores `Entry` values under digest keys. v1 stored bare timestamps under
    /// separator-joined IDs, which neither survives the key change (#4542) nor carries
    /// the recency needed to prune (#4543), so its entries are dropped rather than
    /// migrated — the cost is one restored playback position per pad, once.
    static let defaultsKey = "padHistoryPlaybackPositions.v2"
    private static let legacyDefaultsKey = "padHistoryPlaybackPositions"

    /// Roughly a session's worth of distinct file sets. Playback position is a
    /// convenience, so a bounded working set is worth more than perfect recall of a pad
    /// the user last opened months ago.
    static let entryLimit = 256

    private static let logger = Logger(subsystem: "com.coderpad.app", category: "playback-position")

    /// History IDs are server strings, so no separator is safe to join on: `["a\u{1F}b"]`
    /// and `["a", "b"]` joined to the same key and restored each other's revision (#4542).
    /// Length-prefixing each component makes the encoding unambiguous whatever the IDs
    /// contain, and the digest keeps the key bounded however many files a pad has.
    struct Scope {
        let accountID: UUID
        let padID: String
    }

    static let maximumHistoryCount = 128
    static let maximumHistoryIDBytes = 1024

    static func key(for histories: [PadFileHistory], scope: Scope? = nil) -> String {
        guard let scope, scope.padID.utf8.prefix(65).count <= 64,
              PadIDValidation.normalize(scope.padID) == scope.padID,
              !histories.isEmpty, histories.count <= maximumHistoryCount else { return "" }

        var ids: [String] = []
        for history in histories {
            guard history.id.utf8.prefix(maximumHistoryIDBytes + 1).count <= maximumHistoryIDBytes else { return "" }

            ids.append(history.id)
        }
        var digest = SHA256()
        for id in ["account-pad-v1", scope.accountID.uuidString, scope.padID] + ids.sorted() {
            let encoded = Data(id.utf8)
            digest.update(data: Data(withUnsafeBytes(of: UInt64(encoded.count).bigEndian, Array.init)))
            digest.update(data: encoded)
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func timestamp(for key: String, defaults: UserDefaults = .standard) -> Int64? {
        guard !key.isEmpty else { return nil }

        return savedPositions(defaults: defaults)[key]?.timestamp
    }

    static func position(
        in timeline: PadPlaybackTimeline, histories: [PadFileHistory], scope: Scope? = nil
    ) -> Int {
        let savedTimestamp = timestamp(for: key(for: histories, scope: scope))
        guard let savedTimestamp else { return max(0, timeline.items.count - 1) }

        return timeline.items.lastIndex(where: { $0.timestamp <= savedTimestamp }) ?? 0
    }

    /// A nil `timestamp` means the position no longer exists on the current timeline, so
    /// the stored entry is removed. Leaving it in place restored a revision from a
    /// timeline that had since changed (#4544).
    @discardableResult
    static func save(
        _ timestamp: Int64?,
        for key: String,
        now: Double = Date.timeIntervalSinceReferenceDate,
        defaults: UserDefaults = .standard,
        encode: ([String: Entry]) throws -> Data = { try JSONEncoder().encode($0) }
    ) -> Bool {
        guard !key.isEmpty else { return false }

        var positions = savedPositions(defaults: defaults)
        if let timestamp {
            positions[key] = Entry(timestamp: timestamp, savedAt: now)
            positions = pruned(positions, keeping: key)
        } else if positions.removeValue(forKey: key) == nil {
            // Nothing stored for this set, so there is no write to make.
            return false
        }

        do {
            try defaults.set(encode(positions), forKey: defaultsKey)
            return true
        } catch {
            logger.error("Could not encode playback positions; existing saved positions remain unchanged: \(error)")
            return false
        }
    }

    /// Evicts least-recently-saved entries down to `entryLimit`. The entry just written is
    /// always kept, so a save can never be silently discarded by its own prune.
    private static func pruned(_ positions: [String: Entry], keeping key: String) -> [String: Entry] {
        guard positions.count > entryLimit else { return positions }

        let evictable = positions
            .filter { $0.key != key }
            // Ties broken by key so every device prunes the same entries.
            .sorted { ($0.value.savedAt, $0.key) > ($1.value.savedAt, $1.key) }
            .prefix(entryLimit - 1)
        var kept = Dictionary(uniqueKeysWithValues: evictable.map { ($0.key, $0.value) })
        kept[key] = positions[key]
        return kept
    }

    private static func savedPositions(defaults: UserDefaults = .standard) -> [String: Entry] {
        // Clearing v1 keeps a stale, unreadable blob from sitting in defaults forever.
        if defaults.object(forKey: legacyDefaultsKey) != nil {
            defaults.removeObject(forKey: legacyDefaultsKey)
        }
        guard let data = defaults.data(forKey: defaultsKey) else { return [:] }

        do {
            return try JSONDecoder().decode([String: Entry].self, from: data)
        } catch {
            logger.error("Discarding corrupt playback positions: \(error)")
            defaults.removeObject(forKey: defaultsKey)
            return [:]
        }
    }
}

private struct PlaybackPositionModifier: ViewModifier {
    @Binding var position: Int
    let timeline: PadPlaybackTimeline
    let histories: [PadFileHistory]
    let scope: PlaybackPositionStore.Scope?
    let isPlaying: Bool

    func body(content: Content) -> some View {
        content
            .onChange(of: position) {
                // Playback walks `position` a frame at a time, and encoding and rewriting
                // the whole dictionary on each one made replay progressively more
                // expensive for no benefit — only where the user stops matters (#4723).
                // Announcing every frame would equally flood VoiceOver, so both are the
                // business of a deliberate scrub.
                guard !isPlaying else { return }

                persist()
                AccessibilityNotification.Announcement(
                    String(localized: "History revision \(position + 1) of \(timeline.items.count)")
                ).post()
            }
            // Pausing and leaving are the two moments a replayed position becomes the
            // position worth restoring, so each gets the write the frames skipped.
            .onChange(of: isPlaying) {
                if !isPlaying {
                    persist()
                }
            }
            .onDisappear { persist() }
    }

    private func persist() {
        let timestamp = timeline.items.indices.contains(position) ? timeline.items[position].timestamp : nil
        PlaybackPositionStore.save(timestamp, for: PlaybackPositionStore.key(for: histories, scope: scope))
    }
}

extension View {
    func persistPlaybackPosition(
        _ position: Binding<Int>, timeline: PadPlaybackTimeline,
        histories: [PadFileHistory], scope: PlaybackPositionStore.Scope?, isPlaying: Bool
    ) -> some View {
        modifier(PlaybackPositionModifier(
            position: position, timeline: timeline, histories: histories, scope: scope, isPlaying: isPlaying
        ))
    }
}
