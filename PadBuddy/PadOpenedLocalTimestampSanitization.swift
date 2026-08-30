//
//  PadOpenedLocalTimestampSanitization.swift
//  coderpad
//

import Foundation

extension PadOpenedStore {
    /// How far ahead of this device a timestamp may be before it is treated as a
    /// misconfigured clock rather than skew.
    static let futureClockTolerance: TimeInterval = 5 * 60

    /// Pulls timestamps from a badly-set clock back to now. A small tolerance
    /// absorbs ordinary clock skew between machines.
    static func clampingFutureDates(_ entries: [String: Date], now: Date = Date()) -> [String: Date] {
        let ceiling = now.addingTimeInterval(futureClockTolerance)
        guard entries.contains(where: { $0.value > ceiling }) else { return entries }

        return entries.mapValues { $0 > ceiling ? now : $0 }
    }

    static func clampedLocalTimestamps(
        entries: [String: Date],
        tombstones: [String: Date],
        now: Date
    ) -> (entries: [String: Date], tombstones: [String: Date]) {
        (
            clampingFutureDates(entries, now: now),
            clampingFutureDates(tombstones, now: now)
        )
    }
}
