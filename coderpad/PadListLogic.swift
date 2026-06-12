//
//  PadListLogic.swift
//  coderpad
//
//  Pure, view-independent helpers extracted from PadsView so the filter,
//  date-range, and event-grouping behavior can be exercised by unit tests
//  without standing up a SwiftUI view. PadsView builds its `filtered` list and
//  events log on top of these.
//

import Foundation

/// The lower bound a pad's `updatedAt` must satisfy for a named date-range
/// filter. `now` is injectable so tests are deterministic rather than depending
/// on the wall clock.
enum PadDateRange {
    /// The labels used both for the filter chips and as the keys understood here.
    static let options = ["today", "last 7 days", "last 30 days"]

    /// The earliest `updatedAt` a pad may have to satisfy `option`, or `nil` for
    /// an unrecognized option (treated as "no lower bound").
    static func start(for option: String,
                      now: Date = Date(),
                      calendar: Calendar = .current) -> Date? {
        switch option {
        case "today": return calendar.startOfDay(for: now)
        case "last 7 days": return calendar.date(byAdding: .day, value: -7, to: now)
        case "last 30 days": return calendar.date(byAdding: .day, value: -30, to: now)
        default: return nil
        }
    }
}

/// The set of filters the pad list applies. A `nil` field means "don't filter on
/// this", matching the optional `@State` filters in PadsView one-for-one.
struct PadFilterCriteria {
    var search: String = ""
    var state: PadState? = nil
    /// Expected lowercase, mirroring the language chips; compared case-insensitively.
    var language: String? = nil
    var owner: String? = nil
    var team: String? = nil
    /// An `InterviewType.rawValue` ("live" / "take-home").
    var type: String? = nil
    /// A `PadDateRange.options` label.
    var dateRange: String? = nil
}

enum PadListLogic {
    /// Filter `pads` by `criteria`. `display` resolves an owner email to a display
    /// name so a search can match the human-readable owner as well as the raw
    /// email; it defaults to the identity so callers without a directory still
    /// match on the email. `now` backs the date-range filter.
    static func filter(_ pads: [Pad],
                       using criteria: PadFilterCriteria,
                       now: Date = Date(),
                       display: (String) -> String = { $0 }) -> [Pad] {
        let lowered = criteria.search.lowercased()
        let language = criteria.language?.lowercased()
        let rangeStart = criteria.dateRange.flatMap { PadDateRange.start(for: $0, now: now) }
        return pads.filter { pad in
            (criteria.state == nil || pad.status == criteria.state) &&
            (language == nil || (pad.language ?? "").lowercased() == language) &&
            (criteria.owner == nil || pad.ownerEmail == criteria.owner) &&
            (criteria.team == nil || pad.team?.name == criteria.team) &&
            (criteria.type == nil || pad.interviewType?.rawValue == criteria.type) &&
            (rangeStart.map { (pad.updatedAt ?? .distantPast) >= $0 } ?? true) &&
            (lowered.isEmpty
             || pad.title.lowercased().contains(lowered)
             || pad.id.lowercased().contains(lowered)
             || pad.ownerEmail.lowercased().contains(lowered)
             || display(pad.ownerEmail).lowercased().contains(lowered)
             || pad.participants.contains(where: { $0.lowercased().contains(lowered) }))
        }
    }
}

/// A run of consecutive same-kind, same-user events collapsed into a single row.
/// `representative` is the first event in the run (its kind/user/start time drive
/// the label) and `lastEvent` is the most recent, so the UI can show a time range.
struct PadEventGroup: Identifiable {
    let id: String
    let representative: PadEvent
    let count: Int
    let lastEvent: PadEvent
}

enum PadEventGrouping {
    /// Event kinds that are noisy enough to collapse when they repeat back-to-back
    /// from the same user (typing/editing/running). Lifecycle events like
    /// joined/left/started/ended are always shown individually.
    static let collapsibleKinds: Set<String> = ["typed", "edited", "ran", "executed"]

    /// Collapse consecutive runs of a collapsible kind by the same user into one
    /// group each. Expects `events` in chronological (oldest-first) order so a run
    /// reads as an earliest-to-latest range. Non-collapsible kinds, kind changes,
    /// and user changes all start a fresh group.
    static func group(_ events: [PadEvent]) -> [PadEventGroup] {
        var groups: [PadEventGroup] = []
        for event in events {
            if let last = groups.last,
               collapsibleKinds.contains(event.kind.lowercased()),
               last.representative.kind == event.kind,
               last.representative.userName == event.userName {
                groups[groups.count - 1] = PadEventGroup(
                    id: last.id,
                    representative: last.representative,
                    count: last.count + 1,
                    lastEvent: event
                )
            } else {
                groups.append(PadEventGroup(id: event.id, representative: event, count: 1, lastEvent: event))
            }
        }
        return groups
    }
}
