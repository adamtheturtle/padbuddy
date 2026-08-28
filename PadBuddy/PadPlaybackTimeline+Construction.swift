//
//  PadPlaybackTimeline+Construction.swift
//  coderpad
//

import Foundation

nonisolated extension PadPlaybackTimeline {
    /// How far ahead of the current clock a history timestamp may be and still be
    /// used. Edits cannot legitimately be in the future, so anything past this is a
    /// bad stamp rather than a long session; the window covers ordinary skew between
    /// the device and the backend.
    static let futureTimestampTolerance: TimeInterval = 24 * 60 * 60

    static func mergedItems(from histories: [PadFileHistory], now: Date = Date()) -> [PadPlaybackItem] {
        // Items are keyed by file id. Keep only the first duplicate history so
        // identities and per-file snapshot lookup cannot collide (#1165).
        var seenIDs = Set<String>()
        let uniqueHistories = histories.filter { seenIDs.insert($0.id).inserted }

        // The monotonic lift below is one-directional and was unbounded within
        // `timestampRange`, so one snapshot stamped far in the future became the
        // floor for every later snapshot in its file: all of them collapsed onto that
        // instant, and the scrubber compressed the whole session into a sliver
        // (#4797). A timestamp beyond this ceiling is treated as unusable — the same
        // way `runMarkers` simply draws no marker for an event outside the range —
        // rather than adopted.
        let usableUpperBound = min(timestampRange.upperBound,
                                   Int64((now.timeIntervalSince1970 + futureTimestampTolerance) * 1000))
        // One author spelled two ways is one participant. Keyed on the normalized
        // identity, with the first raw spelling standing in for the group, so the
        // lanes, palette, and position index below cannot split it (#4795).
        var canonicalAuthors: [String: String] = [:]

        var merged: [PadPlaybackItem] = []
        for history in uniqueHistories {
            let clampedTimestamps = history.snapshots.map {
                min(max($0.entry.timestamp, timestampRange.lowerBound), timestampRange.upperBound)
            }
            // A file whose leading snapshots are all unusable starts at its first
            // usable one rather than at the epoch.
            var previousTimestamp = clampedTimestamps.first(where: { $0 <= usableUpperBound })
                ?? timestampRange.lowerBound
            // Lift backwards timestamps to their predecessor so snapshots of one
            // file remain causal despite clock skew in the remote feed (#1879).
            for (snapshot, clamped) in zip(history.snapshots, clampedTimestamps) {
                let monotonic = clamped <= usableUpperBound ? max(clamped, previousTimestamp)
                    : previousTimestamp
                previousTimestamp = monotonic
                let raw = snapshot.entry.author
                let canonical = canonicalAuthors[PadPlaybackAuthors.identityKey(raw), default: raw]
                canonicalAuthors[PadPlaybackAuthors.identityKey(raw)] = canonical
                merged.append(PadPlaybackItem(
                    fileID: history.id,
                    snapshotIndex: snapshot.index,
                    timestamp: monotonic,
                    author: canonical
                ))
            }
        }
        // Deterministic tie-breakers make equal-time edits independent of the
        // order in which the API returned the files (#1880).
        merged.sort {
            ($0.timestamp, $0.fileID, $0.snapshotIndex)
                < ($1.timestamp, $1.fileID, $1.snapshotIndex)
        }
        return merged
    }
}
