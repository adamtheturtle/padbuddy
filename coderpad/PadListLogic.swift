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

/// One date-range constraint: a named window key (one of `PadDateRange.options`)
/// and/or an explicit custom range. A custom range overrides the named window. An
/// all-nil window imposes no constraint. The pad list carries two of these — one
/// applied to the updated date, one to the created date — so they can be filtered
/// independently and at the same time.
struct PadDateWindow: Equatable, Hashable, Codable {
    var range: String? = nil
    var customStart: Date? = nil
    var customEnd: Date? = nil

    var isActive: Bool {
        range != nil || customStart != nil || customEnd != nil
    }

    /// Whether `value` falls within this window. `now` resolves a named window to a
    /// lower bound; a custom range supplies explicit inclusive bounds. An inactive
    /// window contains everything.
    func contains(_ value: Date, now: Date) -> Bool {
        let lower = customStart ?? range.flatMap { PadDateRange.start(for: $0, now: now) }
        return (lower.map { value >= $0 } ?? true)
            && (customEnd.map { value <= $0 } ?? true)
    }
}

/// The lower bound a pad's date must satisfy for a named date-range filter. `now`
/// is injectable so tests are deterministic rather than depending on the wall
/// clock.
enum PadDateRange {
    /// The labels used both for the filter chips and as the keys understood here.
    static let options = ["today", "last 24 hours", "last 7 days", "last 30 days", "last 90 days"]

    /// The earliest date a pad may have to satisfy `option`, or `nil` for an
    /// unrecognized option (treated as "no lower bound").
    ///
    /// Multi-day windows anchor to *calendar-day* boundaries rather than a rolling
    /// count of hours, so "last 7 days" means today plus the six prior whole days
    /// and stays stable as the clock advances through the day (matching Gmail /
    /// Linear). "Last 24 hours" is the deliberate exception — it names an hour
    /// window, so it rolls.
    static func start(for option: String,
                      now: Date = Date(),
                      calendar: Calendar = .current) -> Date? {
        let startOfToday = calendar.startOfDay(for: now)
        switch option {
        case "today": return startOfToday
        case "last 24 hours": return calendar.date(byAdding: .hour, value: -24, to: now)
        case "last 7 days": return calendar.date(byAdding: .day, value: -6, to: startOfToday)
        case "last 30 days": return calendar.date(byAdding: .day, value: -29, to: startOfToday)
        case "last 90 days": return calendar.date(byAdding: .day, value: -89, to: startOfToday)
        default: return nil
        }
    }
}

/// The set of filters the pad list applies. A `nil` field means "don't filter on
/// this", matching the optional `@State` filters in PadsView one-for-one.
struct PadFilterCriteria {
    var search: String = ""
    var state: PadState?
    /// Expected lowercase, mirroring the language chips; compared case-insensitively.
    var language: String?
    var owner: String?
    var team: String?
    /// An `InterviewType.rawValue` ("live" / "take-home").
    var type: String?
    /// Date constraints applied independently and together: `updated` is compared
    /// against the pad's updated date (falling back to created), `created` against
    /// its created date. A pad must satisfy every active window.
    var updated = PadDateWindow()
    var created = PadDateWindow()
}

enum PadListLogic {
    /// Whether a pad should show the "new activity" dot: it's a *started* pad that
    /// has been updated since the user last opened it. A pad never opened (nil
    /// `lastOpened`) shows no dot — "since last open" has no meaning yet — and only
    /// started pads qualify, since activity on ended/pending pads isn't actionable.
    static func hasNewActivitySinceOpen(_ pad: Pad, lastOpened: Date?) -> Bool {
        guard pad.status == .active, let lastOpened, let updated = pad.updatedAt else { return false }
        return updated > lastOpened
    }

    /// Started pads in `pads` — the targets of a bulk "End started pads".
    static func startedPads(in pads: [Pad]) -> [Pad] {
        pads.filter { $0.status == .active }
    }

    /// Pads in `pads` not already private — the targets of a bulk "Make private".
    static func nonPrivatePads(in pads: [Pad]) -> [Pad] {
        pads.filter { $0.isPrivate != true }
    }

    /// The auto-refresh cadence for the pad list. Backs off as the list grows (large
    /// orgs poll less often) and backs off a further 2× when no pad is started, since
    /// with no live interview in progress the list is unlikely to be changing — so
    /// refresh effort is biased toward when started pads are actually present.
    static func refreshInterval(base: Duration, padCount: Int, hasStartedPads: Bool) -> Duration {
        var interval: Duration = switch padCount {
        case ..<500: base
        case 500 ..< 2000: base * 2
        default: base * 4
        }
        if !hasStartedPads { interval *= 2 }
        return interval
    }

    /// Filter `pads` by `criteria`. `display` resolves an owner email to a display
    /// name so a search can match the human-readable owner as well as the raw
    /// email; it defaults to the identity so callers without a directory still
    /// match on the email. `now` backs the date-range filter.
    static func filter(_ pads: [Pad],
                       using criteria: PadFilterCriteria,
                       now: Date = Date(),
                       display: (String) -> String = { $0 }) -> [Pad] {
        pads.filter { matches($0, criteria: criteria, now: now, display: display) }
    }

    /// Whether a single pad satisfies `criteria`. Factored out of `filter` so the
    /// combined "All Accounts" list can filter account-tagged rows one at a time
    /// (keeping each row's source account) while reusing the exact same predicate
    /// the single-account list uses, so the two can never drift.
    static func matches(_ pad: Pad,
                        criteria: PadFilterCriteria,
                        now: Date = Date(),
                        display: (String) -> String = { $0 }) -> Bool {
        let lowered = criteria.search.lowercased()
        let language = criteria.language?.lowercased()
        // The dates each window compares against. `.distantPast` so a pad with no
        // dates is excluded by any lower bound rather than crashing on a force-unwrap.
        let updatedValue = (pad.updatedAt ?? pad.createdAt) ?? .distantPast
        let createdValue = pad.createdAt ?? .distantPast
        return (criteria.state == nil || pad.status == criteria.state) &&
            (language == nil || (pad.language ?? "").lowercased() == language) &&
            (criteria.owner == nil || pad.ownerEmail == criteria.owner) &&
            (criteria.team == nil || pad.team?.name == criteria.team) &&
            (criteria.type == nil || pad.interviewType?.rawValue == criteria.type) &&
            criteria.updated.contains(updatedValue, now: now) &&
            criteria.created.contains(createdValue, now: now) &&
            (lowered.isEmpty
                || pad.title.lowercased().contains(lowered)
                || pad.id.lowercased().contains(lowered)
                || pad.ownerEmail.lowercased().contains(lowered)
                || display(pad.ownerEmail).lowercased().contains(lowered)
                || pad.participants.contains(where: { $0.lowercased().contains(lowered) }))
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
