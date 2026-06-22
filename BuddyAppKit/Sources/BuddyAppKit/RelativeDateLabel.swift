//
//  RelativeDateLabel.swift
//  BuddyAppKit
//

import Foundation

/// Caches a date's relative ("2 hours ago") and absolute tooltip strings so list
/// rows don't pay `Date.formatted(.relative:)`'s cost on every render.
///
/// `Date.formatted(.relative(presentation:))` re-creates its formatting machinery on
/// every call, and a `List` re-evaluates every visible row's body on each selection
/// pass — so on a large list this dominated the per-click cost (measured ~46% of the
/// stall on a 2500-pad list). The label is a pure function of the date and the current
/// time, so it's keyed by the date within a coarse time bucket: repeated reads within a
/// bucket hit the cache, and when the bucket rolls over the cache clears so relative
/// strings stay fresh. The strings are produced by the same `formatted` calls the rows
/// used inline, so the displayed wording is unchanged. Main-actor only, matching the
/// list rows that read it.
@MainActor
public enum RelativeDateLabel {
    public struct Labels {
        public let relative: String
        public let tooltip: String
    }

    private static var cache: [Date: Labels] = [:]
    private static var bucket = 0
    /// Relative wording is coarse (minutes/hours/days), so a 30-second refresh window is
    /// imperceptible while keeping the cache hot across a selection's several renders.
    private static let bucketSeconds = 30.0

    public static func labels(for date: Date) -> Labels {
        let now = Int(Date().timeIntervalSinceReferenceDate / bucketSeconds)
        if now != bucket {
            cache.removeAll(keepingCapacity: true)
            bucket = now
        }
        if let hit = cache[date] {
            return hit
        }

        let labels = Labels(
            relative: date.formatted(.relative(presentation: .named)),
            tooltip: date.formatted(date: .long, time: .shortened)
        )
        cache[date] = labels
        return labels
    }
}
