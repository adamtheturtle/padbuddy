//
//  StatsPeriod.swift
//  coderpad
//
//  The selectable window for organization pad-usage stats and the request-identity
//  token both Organization views guard their async stats publishes with. Split from
//  OrganizationView.swift to keep it within the lint length limit.
//

import Foundation

/// Selectable window for the organization pad-usage stats. `nil` dates mean the
/// API's own default (last 7 days); the presets compute an explicit range.
enum StatsPeriod: String, CaseIterable, Identifiable {
    static let maximumCustomMonths = 12
    case days7 = "Last 7 days"
    case days30 = "Last 30 days"
    case days90 = "Last 90 days"
    case months12 = "Last 12 months"
    case custom = "Custom range"

    var id: String {
        rawValue
    }

    var displayLabel: String {
        switch self {
        case .custom: String(localized: "Custom range")
        case .months12: String(localized: "Last 12 months")
        case .days90: String(localized: "Last 90 days")
        default: rawValue
        }
    }

    private var days: Int? {
        switch self {
        case .days7: 7
        case .days30: 30
        case .days90: 90
        case .months12, .custom: nil
        }
    }

    /// The (start, end) window ending now for the selected preset, or `nil` for
    /// `.custom` where the dates come from the view's own pickers. "Last N days"
    /// covers exactly N calendar dates — today plus the N-1 previous ones,
    /// anchored at the first day's start; subtracting N whole days from `now`
    /// included a sliver of an (N+1)th date, so the preset label and the
    /// analytics window disagreed (#1657). "Last 12 months" subtracts calendar
    /// months rather than a fixed 365 days (#1658).
    func range(now: Date = Date()) -> (start: Date, end: Date)? {
        let calendar = Calendar.current
        if self == .months12 {
            let anchor = calendar.date(byAdding: .month, value: -12, to: now) ?? now
            return (calendar.startOfDay(for: anchor), now)
        }
        guard let days else { return nil }

        let anchor = calendar.date(byAdding: .day, value: -(days - 1), to: now) ?? now
        return (calendar.startOfDay(for: anchor), now)
    }

    /// Sanitizes user-selected analytics dates before they reach the API. Future,
    /// inverted, and multi-year windows otherwise produce expensive or misleading
    /// requests (#1519).
    static func boundedCustomRange(
        start: Date,
        end: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> (start: Date, end: Date) {
        let boundedEnd = min(end, now)
        let earliest = calendar.date(byAdding: .month, value: -maximumCustomMonths, to: boundedEnd) ?? boundedEnd
        return (min(max(start, earliest), boundedEnd), boundedEnd)
    }

    static func persistedCustomRange(
        scope: String,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) -> (start: Date, end: Date) {
        let startKey = "organization.customRange.\(scope).start"
        let endKey = "organization.customRange.\(scope).end"
        let fallbackStart = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        guard defaults.object(forKey: startKey) != nil,
              defaults.object(forKey: endKey) != nil
        else { return (fallbackStart, now) }

        return boundedCustomRange(
            start: Date(timeIntervalSince1970: defaults.double(forKey: startKey)),
            end: Date(timeIntervalSince1970: defaults.double(forKey: endKey)),
            now: now
        )
    }

    @discardableResult
    static func persistCustomRange(
        start: Date,
        end: Date,
        scope: String,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) -> (start: Date, end: Date) {
        let range = boundedCustomRange(start: start, end: end, now: now)
        defaults.set(range.start.timeIntervalSince1970, forKey: "organization.customRange.\(scope).start")
        defaults.set(range.end.timeIntervalSince1970, forKey: "organization.customRange.\(scope).end")
        return range
    }
}

/// Identity of the stats window a request was made for: the period preset plus
/// the custom dates when applicable. Publishing guards compare this rather than
/// the resolved (start, end) dates, whose now-anchored end differs on every
/// read and can never compare equal (#798).
nonisolated struct StatsWindowToken: Equatable {
    let period: StatsPeriod
    let customStart: Date?
    let customEnd: Date?
}
