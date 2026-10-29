import Foundation

/// Preserve ordinary device clock skew without letting a broken remote clock
/// pin local last-writer-wins state arbitrarily far into the future.
nonisolated enum FutureTimestampPolicy {
    static let clockSkewTolerance: TimeInterval = 5 * 60

    static func clamped(_ timestamp: Date, now: Date = Date()) -> Date {
        guard timestamp.timeIntervalSinceReferenceDate.isFinite else { return now }

        return timestamp > now.addingTimeInterval(clockSkewTolerance) ? now : timestamp
    }

    static func clamped(_ entries: [String: Date], now: Date = Date()) -> [String: Date] {
        entries.mapValues { clamped($0, now: now) }
    }
}
