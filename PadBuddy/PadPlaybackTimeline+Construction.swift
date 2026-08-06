//
//  PadPlaybackTimeline+Construction.swift
//  coderpad
//

nonisolated extension PadPlaybackTimeline {
    static func mergedItems(from histories: [PadFileHistory]) -> [PadPlaybackItem] {
        // Items are keyed by file id. Keep only the first duplicate history so
        // identities and per-file snapshot lookup cannot collide (#1165).
        var seenIDs = Set<String>()
        let uniqueHistories = histories.filter { seenIDs.insert($0.id).inserted }

        var merged: [PadPlaybackItem] = []
        for history in uniqueHistories {
            // Lift backwards timestamps to their predecessor so snapshots of one
            // file remain causal despite clock skew in the remote feed (#1879).
            var previousTimestamp = timestampRange.lowerBound
            for snapshot in history.snapshots {
                let clamped = min(max(snapshot.entry.timestamp, timestampRange.lowerBound),
                                  timestampRange.upperBound)
                let monotonic = max(clamped, previousTimestamp)
                previousTimestamp = monotonic
                merged.append(PadPlaybackItem(
                    fileID: history.id,
                    snapshotIndex: snapshot.index,
                    timestamp: monotonic,
                    author: snapshot.entry.author
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
