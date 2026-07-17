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
    case days7 = "Last 7 days"
    case days30 = "Last 30 days"
    case days90 = "Last 90 days"
    case months12 = "Last 12 months"
    case custom = "Custom range"

    /// `@AppStorage` key shared by the Organization view and the View menu's
    /// "Stats Period" command, so the toolbar picker and the menu stay in sync.
    static let storageKey = "organization.statsPeriod"

    var id: String {
        rawValue
    }

    private var days: Int? {
        switch self {
        case .days7: 7
        case .days30: 30
        case .days90: 90
        case .months12: 365
        case .custom: nil
        }
    }

    /// The (start, end) window ending now for the selected preset, or `nil` for
    /// `.custom` where the dates come from the view's own pickers.
    func range(now: Date = Date()) -> (start: Date, end: Date)? {
        guard let days else { return nil }

        let start = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        return (start, now)
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
