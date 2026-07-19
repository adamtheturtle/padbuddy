//
//  SharedDateStyles.swift
//  coderpad
//
//  Date format styles built once and shared.
//
//  `Date.formatted(date:time:)` and the `.dateTime` builders construct a fresh
//  `Date.FormatStyle` on every call. Several of the app's hottest paths call them
//  once per row or per grouped event, inside a body that re-runs on every render —
//  so the formatting machinery was rebuilt per element, per pass (#2428–#2435).
//  A `Date.FormatStyle` is a value type that carries no mutable state once
//  configured, so one instance is safe to share.
//

import Foundation

enum SharedDateStyles {
    /// "3 Feb 2026" — list rows that show a day but no time.
    static let day = Date.FormatStyle(date: .abbreviated, time: .omitted)

    /// "3 February 2026 at 14:05" — timeline entries that need the full date.
    static let longDateAndTime = Date.FormatStyle(date: .long, time: .shortened)

    /// "14:05" — the second endpoint of a same-day range, where repeating the date
    /// would be noise.
    static let timeOnly = Date.FormatStyle(date: .omitted, time: .shortened)

    /// "3 February 2026" — a full date with no time, as in the quota reset rows.
    static let longDate = Date.FormatStyle(date: .long, time: .omitted)

    /// "March 1" — the endpoints of a custom date-range filter chip.
    static let monthAndDay = Date.FormatStyle.dateTime.month(.wide).day()
}
