//
//  PadEventRetention.swift
//  coderpad
//

import CoderPadKit

nonisolated enum PadEventRetention {
    static let maxEventCount = 5000
    static let maxRetainedBytes = 4_000_000

    /// The events endpoint returns newest-first. Retain that bounded prefix before
    /// chronological sorting, grouping, rendering, or cache publication.
    static func newest(from events: [PadEvent]) -> [PadEvent] {
        var retained: [PadEvent] = []
        retained.reserveCapacity(min(events.count, maxEventCount))
        var retainedBytes = 0

        for event in events.prefix(maxEventCount) {
            let eventBytes = 200 + event.kind.utf8.count
                + event.message.utf8.count
                + (event.metadata?.utf8.count ?? 0)
                + (event.userName?.utf8.count ?? 0)
                + (event.userEmail?.utf8.count ?? 0)
            guard eventBytes <= maxRetainedBytes - retainedBytes else { break }

            retained.append(event)
            retainedBytes += eventBytes
        }
        return retained
    }
}
