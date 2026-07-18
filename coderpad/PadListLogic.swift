//
//  PadListLogic.swift
//  coderpad
//
//  Pure, view-independent helpers extracted from PadsView so the filter,
//  date-range, and event-grouping behavior can be exercised by unit tests
//  without standing up a SwiftUI view. PadsView builds its `filtered` list and
//  events log on top of these.
//

import BuddyAppKit
import Foundation

/// The named date-range lower bounds moved to buddy-kit (`NamedDateRange`). This shim
/// forwards the pure parts and keeps `displayLabel` app-side, because its
/// `String(localized:)` lookups must resolve against the app bundle's String Catalog,
/// not the package's.
enum PadDateRange {
    /// The labels used both for the filter chips and as the keys understood here.
    static var options: [String] {
        NamedDateRange.options
    }

    /// A localized, display-ready label for a range key. The raw `options` values
    /// double as match keys, so they're kept verbatim and translated only for
    /// display here (#111). Unknown keys fall back to a capitalized form.
    static func displayLabel(for option: String) -> String {
        switch option {
        case "today": String(localized: "Today")
        case "last 24 hours": String(localized: "Last 24 hours")
        case "last 7 days": String(localized: "Last 7 days")
        case "last 30 days": String(localized: "Last 30 days")
        case "last 90 days": String(localized: "Last 90 days")
        default: option.capitalized
        }
    }

    /// The earliest date a pad may have to satisfy `option`, or `nil` for an
    /// unrecognized option (treated as "no lower bound"). Forwards to
    /// `NamedDateRange.start`; see there for the calendar-day-anchoring rationale.
    static func start(for option: String,
                      now: Date = Date(),
                      calendar: Calendar = .current) -> Date? {
        NamedDateRange.start(for: option, now: now, calendar: calendar)
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
    var updated = DateWindow()
    var created = DateWindow()
}

enum PadListLogic {
    /// Cache token for active date filters. Date windows can depend on the current
    /// time ("Today", "Last 24 hours", etc.), so memoized filter results must move
    /// forward as time does even when the pad data and static filter signature do not.
    static func dateFilterCacheToken(updated: DateWindow, created: DateWindow, now: Date = Date()) -> Int? {
        guard updated.isActive || created.isActive else { return nil }

        return Int(now.timeIntervalSinceReferenceDate / 60)
    }

    /// Whether a pad should show the "new activity" dot: it's a *started* pad that
    /// has been updated since the user last opened it. A pad never opened (nil
    /// `lastOpened`) shows no dot — "since last open" has no meaning yet — and only
    /// started pads qualify, since activity on ended/pending pads isn't actionable.
    static func hasNewActivitySinceOpen(_ pad: Pad, lastOpened: Date?) -> Bool {
        guard pad.status == .active, let lastOpened, let updated = pad.updatedAt else { return false }

        return updated > lastOpened
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
                       display: (String) -> String = \.self) -> [Pad] {
        pads.filter { matches($0, criteria: criteria, now: now, display: display) }
    }

    /// Whether a single pad satisfies `criteria`. Factored out of `filter` so the
    /// combined "All Accounts" list can filter account-tagged rows one at a time
    /// (keeping each row's source account) while reusing the exact same predicate
    /// the single-account list uses, so the two can never drift.
    static func matches(_ pad: Pad,
                        criteria: PadFilterCriteria,
                        now: Date = Date(),
                        display: (String) -> String = \.self) -> Bool {
        let search = criteria.search.trimmingCharacters(in: .whitespacesAndNewlines)
        let language = criteria.language?.lowercased()
        // The dates each window compares against. `.distantPast` so a pad with no
        // dates is excluded by any lower bound rather than crashing on a force-unwrap.
        let updatedValue = (pad.updatedAt ?? pad.createdAt) ?? .distantPast
        let createdValue = pad.createdAt ?? .distantPast
        return (criteria.state == nil || pad.status == criteria.state) &&
            (language == nil || (pad.language ?? "").lowercased() == language) &&
            // Emails are case-insensitive: the Me shortcut or a persisted filter
            // may carry a different casing than the API's owner values (#1643).
            (criteria.owner.map { pad.ownerEmail.caseInsensitiveCompare($0) == .orderedSame } ?? true) &&
            (criteria.team == nil || pad.team?.name == criteria.team) &&
            (criteria.type == nil || pad.interviewType?.rawValue == criteria.type) &&
            criteria.updated.contains(updatedValue, now: now) &&
            criteria.created.contains(createdValue, now: now) &&
            // Locale-aware case-insensitive matching so non-ASCII titles/names fold
            // correctly for the user's locale (plain `.lowercased()` mishandles some
            // scripts, e.g. the Turkish dotted/dotless I).
            (search.isEmpty
                || pad.title.localizedCaseInsensitiveContains(search)
                || pad.id.localizedCaseInsensitiveContains(search)
                || pad.ownerEmail.localizedCaseInsensitiveContains(search)
                || display(pad.ownerEmail).localizedCaseInsensitiveContains(search)
                || pad.participants.contains(where: { $0.localizedCaseInsensitiveContains(search) }))
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

/// Loaded editor history for one displayable pad file.
nonisolated struct PadFileHistory: Identifiable, Hashable {
    let id: String
    let title: String
    let language: String?
    let history: PadHistory
    let snapshots: [PadHistorySnapshot]

    init(id: String, title: String, language: String?, history: PadHistory) {
        self.id = id
        self.title = title
        self.language = language
        self.history = history

        var contents = ""
        snapshots = history.entries.enumerated().map { index, entry in
            contents = entry.applying(to: contents)
            return PadHistorySnapshot(index: index, entry: entry, contents: contents,
                                      changeLine: Self.changeLine(of: entry, in: contents))
        }
    }

    var latestEntry: PadHistoryEntry? {
        history.entries.last
    }

    /// The 0-based line an entry's edit lands on in the post-edit contents, so
    /// playback can scroll the code to where the change is happening (#983).
    /// The edit position is the entry's leading retain run (operations are an
    /// OT sequence: retains position the cursor, then inserts/deletes act there),
    /// counted in UTF-16 code units like the history itself.
    private static func changeLine(of entry: PadHistoryEntry, in contents: String) -> Int {
        var offset = 0
        for operation in entry.operations {
            guard case .retain(let count) = operation else { break }
            offset += count
        }
        let newline = "\n".utf16.first
        return contents.utf16.prefix(offset).count(where: { $0 == newline })
    }
}

nonisolated struct PadHistorySnapshot: Identifiable, Hashable {
    var id: String {
        entry.id
    }

    let index: Int
    let entry: PadHistoryEntry
    let contents: String
    /// The 0-based line of this entry's edit; see `PadFileHistory.changeLine`.
    let changeLine: Int
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
               last.representative.kind.lowercased() == event.kind.lowercased(),
               let lastActor = actorKey(for: last.representative),
               lastActor == actorKey(for: event) {
                groups[groups.count - 1] = PadEventGroup(
                    id: last.id,
                    representative: last.representative,
                    count: last.count + 1,
                    lastEvent: event
                )
            } else {
                // Two distinct events can share an `event.id` (same timestamp, kind,
                // user, and message, e.g. duplicate `enabled_ai_assist` entries), so
                // prefix the group position to keep ForEach identities unique.
                groups.append(PadEventGroup(id: "\(groups.count)-\(event.id)",
                                            representative: event,
                                            count: 1,
                                            lastEvent: event))
            }
        }
        return groups
    }

    private static func actorKey(for event: PadEvent) -> String? {
        if let email = event.userEmail?.trimmingCharacters(in: .whitespacesAndNewlines),
           !email.isEmpty {
            return "email:\(email.lowercased())"
        }

        if let name = event.userName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return "name:\(name)"
        }

        return nil
    }
}
