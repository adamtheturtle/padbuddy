import Foundation

nonisolated enum PadHistoryTimestampPolicy {
    static let maximumBackwardSkew: Int64 = 5 * 60 * 1000

    static func admitted(_ timestamp: Int64, after previous: Int64?, now: Date) -> Int64? {
        let milliseconds = (now.timeIntervalSince1970 + PadPlaybackTimeline.futureTimestampTolerance) * 1000
        guard milliseconds.isFinite else { return nil }

        let ceiling = Int64(min(max(milliseconds, 0), Double(PadPlaybackTimeline.timestampRange.upperBound)))
        guard timestamp >= 0, timestamp <= ceiling else { return nil }

        if let previous {
            guard previous >= 0, previous <= PadPlaybackTimeline.timestampRange.upperBound else { return nil }
            guard timestamp >= previous - maximumBackwardSkew else { return nil }

            return max(timestamp, previous)
        }
        return timestamp
    }
}
