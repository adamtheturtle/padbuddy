//
//  PadOpenedFutureDateResolution.swift
//  coderpad
//

import Foundation

extension PadOpenedStore {
    static func resolveClampingFutureDates(
        entries: [String: Date],
        tombstones: [String: Date],
        now: Date = Date()
    ) -> (entries: [String: Date], tombstones: [String: Date]) {
        CloudTombstones.resolveTimestamps(
            entries: clampingFutureDates(entries, now: now),
            tombstones: clampingFutureDates(tombstones, now: now)
        )
    }
}
