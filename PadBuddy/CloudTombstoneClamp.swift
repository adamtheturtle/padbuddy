//
//  CloudTombstoneClamp.swift
//  coderpad
//
//  The membership half of every mirrored favourites blob is clamped on arrival
//  because the mirror is cross-device input that oversized data can make expensive
//  to hold, sort, and re-upload (#1788). The tombstone half of the same blob was
//  taken verbatim: `CloudTombstones.pruned` ages entries out by date, so anything
//  stamped recently survived, and there was no count bound at all (#4815).
//

import Foundation

/// Bounds a decoded cloud tombstone blob to the same per-account count as its
/// membership counterpart.
enum CloudTombstoneClamp {
    /// Keeps the `limit` most recent removals for one account.
    ///
    /// Newest-first because an old tombstone is the one `CloudTombstones.pruned`
    /// would age out next anyway, so dropping it costs the least convergence. Ties
    /// break on the id so every device clamps an identical blob identically —
    /// otherwise two devices would each re-upload a different subset and never
    /// settle.
    static func clamped(_ tombstones: [String: Date], limit: Int) -> [String: Date] {
        guard tombstones.count > limit else { return tombstones }

        let kept = tombstones
            .sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
            }
            .prefix(limit)
        return Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
    }

    /// Keyed by account sync identity, as the mirrored blob is.
    static func clamped(_ blob: [String: [String: Date]], limit: Int) -> [String: [String: Date]] {
        blob.mapValues { clamped($0, limit: limit) }
    }
}
