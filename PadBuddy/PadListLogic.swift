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

extension PadFilterCriteria {
    /// A criteria set with its free-text fields pre-normalized. `matches` runs once
    /// per pad, so trimming the search and lowercasing the language *inside* it
    /// repeated the same work on the same constant filter strings once per pad —
    /// thousands of redundant allocations per filter pass on a large org (#2098).
    /// Callers that loop build this once, outside the loop, and pass it in.
    struct Normalized {
        let criteria: PadFilterCriteria
        /// `criteria.search` with surrounding whitespace removed.
        let search: String
        /// `criteria.language` lowercased, matching the lowercase language chips.
        let language: String?
        /// Owner/team selections trimmed once before the per-pad predicate runs.
        let owner: String?
        let team: String?

        init(_ criteria: PadFilterCriteria) {
            self.criteria = criteria
            search = criteria.search.trimmingCharacters(in: .whitespacesAndNewlines)
            language = criteria.language?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            owner = criteria.owner?.canonicalOwnerEmail
            team = criteria.team?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    var normalized: Normalized {
        Normalized(self)
    }
}

enum PadListLogic {
    /// Cache token for active date filters. Date windows can depend on the current
    /// time ("Today", "Last 24 hours", etc.), so memoized filter results must move
    /// forward as time does even when the pad data and static filter signature do not.
    ///
    /// The elapsed minute alone isn't enough: "Today" is anchored to the start of the
    /// calendar day, so travelling across time zones — or switching calendar — changes
    /// which pads match without changing the clock reading. Folding the calendar's
    /// identity into the token invalidates those cached results immediately rather than
    /// leaving them under the old interpretation until something unrelated evicts
    /// them (#2008).
    static func dateFilterCacheToken(updated: DateWindow,
                                     created: DateWindow,
                                     now: Date = Date(),
                                     calendar: Calendar = .current) -> Int? {
        guard updated.isActive || created.isActive else { return nil }

        var hasher = Hasher()
        hasher.combine(Int(now.timeIntervalSinceReferenceDate / 60))
        hasher.combine(calendar.identifier)
        hasher.combine(calendar.timeZone.identifier)
        return hasher.finalize()
    }

    /// The auto-refresh cadence for the pad list. Backs off as the list grows (large
    /// orgs poll less often) and backs off a further 2× when no pad is started, since
    /// with no live interview in progress the list is unlikely to be changing — so
    /// refresh effort is biased toward when started pads are actually present.
    static func refreshInterval(base: Duration, padCount: Int, hasStartedPads: Bool) -> Duration {
        var interval: Duration = switch padCount {
        // A negative count is not a real list size, so it can't be trusted to mean
        // "small list". Falling through to the base cadence would hand the fastest
        // poll to the most obviously broken input, so treat it as unknown and use
        // the most conservative back-off instead (#2009).
        case ..<0: base * 4
        case 0 ..< 500: base
        case 500 ..< 2000: base * 2
        default: base * 4
        }
        if !hasStartedPads {
            interval *= 2
        }
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
        let normalized = criteria.normalized
        return pads.filter { matches($0, criteria: normalized, now: now, display: display) }
    }

    /// Whether a single pad satisfies `criteria`. Factored out of `filter` so the
    /// combined "All Accounts" list can filter account-tagged rows one at a time
    /// (keeping each row's source account) while reusing the exact same predicate
    /// the single-account list uses, so the two can never drift.
    static func matches(_ pad: Pad,
                        criteria: PadFilterCriteria,
                        now: Date = Date(),
                        display: (String) -> String = \.self) -> Bool {
        matches(pad, criteria: criteria.normalized, now: now, display: display)
    }

    /// The predicate itself, over pre-normalized criteria so a filter pass normalizes
    /// the constant filter strings once rather than once per pad (#2098).
    static func matches(_ pad: Pad,
                        criteria: PadFilterCriteria.Normalized,
                        now: Date = Date(),
                        display: (String) -> String = \.self) -> Bool {
        let search = criteria.search
        let language = criteria.language
        let owner = criteria.owner
        let team = criteria.team
        let criteria = criteria.criteria
        // The dates each window compares against. `.distantPast` so a pad with no
        // dates is excluded by any lower bound rather than crashing on a force-unwrap.
        let updatedValue = (pad.updatedAt ?? pad.createdAt) ?? .distantPast
        let createdValue = pad.createdAt ?? .distantPast
        return (criteria.state == nil || pad.status == criteria.state) &&
            (language == nil || (pad.language ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() == language) &&
            // Emails are case-insensitive: the Me shortcut or a persisted filter
            // may carry a different casing than the API's owner values (#1643).
            (owner.map { pad.ownerEmail.canonicalOwnerEmail == $0 } ?? true) &&
            // Case-insensitive like the owner comparison above: a team name is a
            // free-text org label, and a saved or migrated filter carrying different
            // casing matched nothing at all (#2488).
            (team.map { team in
                pad.team?.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare(team) == .orderedSame
            } ?? true) &&
            (criteria.type == nil || pad.interviewType?.rawValue == criteria.type) &&
            PadDateWindowValidation.contains(criteria.updated, date: updatedValue, now: now) &&
            PadDateWindowValidation.contains(criteria.created, date: createdValue, now: now) &&
            // Locale-aware case-insensitive matching so non-ASCII titles/names fold
            // correctly for the user's locale (plain `.lowercased()` mishandles some
            // scripts, e.g. the Turkish dotted/dotless I).
            (search.isEmpty
                || pad.title.localizedCaseInsensitiveContains(search)
                || pad.id.localizedCaseInsensitiveContains(search)
                || pad.ownerEmail.localizedCaseInsensitiveContains(search)
                || display(pad.ownerEmail).localizedCaseInsensitiveContains(search)
                || pad.participants.contains(where: {
                    $0.localizedCaseInsensitiveContains(search)
                        || display($0).localizedCaseInsensitiveContains(search)
                }))
    }
}

/// A run of consecutive same-kind, same-user events collapsed into a single row.
/// `representative` and `lastEvent` preserve the time range; `actorEvent` retains
/// the best available actor name independently of the first event.
struct PadEventGroup: Identifiable {
    let id: String
    let representative: PadEvent
    let count: Int
    let lastEvent: PadEvent
    let actorEvent: PadEvent
    let actorIdentity: String?
}

/// Loaded editor history for one displayable pad file.
nonisolated struct PadFileHistory: Identifiable, Hashable {
    struct Checkpoint: Hashable {
        let snapshotIndex: Int
        let contents: String
    }

    let id: String
    let title: String
    let language: String?
    let history: PadHistory
    let snapshots: [PadHistorySnapshot]
    let startingContents: String
    let checkpoints: [Checkpoint]

    /// Remote histories retain a bounded, replayable prefix and report truncation.
    static let maxSnapshotEntries = 10000
    static let maxSnapshotBytes = 64_000_000
    let wasTruncated: Bool
    let retainedHistoryBytes: Int

    init(id: String, title: String, language: String?, history: PadHistory) {
        self.id = id
        self.title = title
        self.language = language
        let built = PadHistoryBuild(history: history)
        self.history = PadHistory(entries: built.snapshots.map(\.entry))
        startingContents = ""
        snapshots = built.snapshots
        checkpoints = built.checkpoints
        wasTruncated = built.wasTruncated
        retainedHistoryBytes = built.retainedBytes
    }

    /// Replays remote history away from the caller's actor. Building snapshots can
    /// apply thousands of edits and repeatedly scan their UTF-8/UTF-16 contents;
    /// detail views call this after an async fetch while isolated to the UI actor.
    static func replaying(id: String, title: String, language: String?, history: PadHistory) async -> Self {
        await Task.detached(priority: .utility) {
            Self(id: id, title: title, language: language, history: history)
        }.value
    }

    var latestEntry: PadHistoryEntry? {
        history.entries.last
    }
}

enum PadEventGrouping {
    /// Event kinds that are noisy enough to collapse when they repeat back-to-back
    /// from the same user (typing/editing/running). Lifecycle events like
    /// joined/left/started/ended are always shown individually.
    static let collapsibleKinds: Set<String> = ["typed", "edited", "ran", "executed"]

    /// The longest idle gap two collapsible events may span and still read as one
    /// run. Collapsing had no time threshold at all, so a `typed` event in the
    /// morning and another in the afternoon merged into a single row and hours of
    /// unrelated activity were summarized as one burst (#2003).
    static let maxCollapseGap: TimeInterval = 5 * 60

    /// Whether `event` is close enough in time to `previous` to continue its run.
    /// Undated events carry no gap information and remain separate. The magnitude
    /// of a known gap prevents merging across a large backwards jump.
    private static func continuesRun(_ event: PadEvent, after previous: PadEvent) -> Bool {
        guard let previousDate = previous.createdAt, let date = event.createdAt else { return false }

        return abs(date.timeIntervalSince(previousDate)) <= maxCollapseGap
    }

    /// Collapse consecutive runs of a collapsible kind by the same user into one
    /// group each. API delivery order is not part of the contract, so events are
    /// normalized oldest-first before grouping; undated events follow dated ones and
    /// equal timestamps preserve their response order. Non-collapsible kinds, kind
    /// changes, user changes, and long idle gaps all start a fresh group.
    static func group(_ events: [PadEvent]) -> [PadEventGroup] {
        var groups: [PadEventGroup] = []
        let ordered = chronological(events)
        let identities = PadEventActorIdentity(events: ordered)
        // The current group's kind, already lowercased. Each event used to lowercase
        // its own kind twice and the representative's once more, so a long timeline
        // walked three strings per event to answer one question (#2454).
        var lastKind: String?
        for event in ordered {
            let kind = PadEventKind.normalized(event.kind)
            if let last = groups.last,
               collapsibleKinds.contains(kind),
               lastKind == kind,
               continuesRun(event, after: last.lastEvent),
               let lastActor = last.actorIdentity,
               lastActor == identities.key(for: event) {
                groups[groups.count - 1] = PadEventGroup(
                    id: last.id,
                    representative: last.representative,
                    count: last.count + 1,
                    lastEvent: event,
                    actorEvent: PadEventActorIdentity.preferredActor(last.actorEvent, latest: event),
                    actorIdentity: lastActor
                )
            } else {
                // Two distinct events can share an `event.identity` (same timestamp, kind,
                // user, and message, e.g. duplicate `enabled_ai_assist` entries), so
                // prefix the group position to keep ForEach identities unique.
                groups.append(PadEventGroup(id: "\(groups.count)-\(identitySuffix(for: event))",
                                            representative: event,
                                            count: 1,
                                            lastEvent: event,
                                            actorEvent: event,
                                            actorIdentity: identities.key(for: event)))
                lastKind = kind
            }
        }
        return groups
    }

    /// How much of an event's own identity a group ID may carry.
    static let maxIdentitySuffixLength = 64

    /// A bounded, normalized form of `event.identity` for use inside a group ID
    /// (#2004). The identity already bounds its remote fields; the
    /// positional prefix already makes each group ID unique, so the event part is
    /// purely diagnostic: strip characters that make identities awkward to log or
    /// compare and cap the length rather than copying an unbounded message into
    /// every SwiftUI view identity.
    static func identitySuffix(for event: PadEvent) -> String {
        String(event.identity.unicodeScalars.lazy
            .map { CharacterSet.controlCharacters.contains($0) ? " " : Character($0) }
            .prefix(maxIdentitySuffixLength))
    }
}
