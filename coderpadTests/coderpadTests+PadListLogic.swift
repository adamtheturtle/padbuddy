//
//  coderpadTests+PadListLogic.swift
//  coderpadTests
//

@testable import CoderPad
import Foundation
import Testing

// MARK: - Pad list logic (filters, date ranges, event grouping)

/// A fixed clock so the date-range tests don't depend on the wall clock, and a
/// UTC calendar so `startOfDay` lands on a known instant regardless of the
/// machine's time zone.
private let fixedNow = ISO8601DateFormatter().date(from: "2026-06-12T12:00:00Z") ?? .distantPast
private var utcCalendar: Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    return cal
}

/// Builds a `Pad` through the real lenient decoder so the tests exercise the
/// same construction path the app uses, rather than a hand-rolled initializer.
private func makePad(
    id: String = "P1",
    title: String = "",
    state: String = "started",
    ownerEmail: String = "",
    language: String? = nil,
    type: String? = nil,
    teamName: String? = nil,
    participants: [String] = [],
    updatedAt: String? = nil,
    createdAt: String? = nil,
    isPrivate: Bool? = nil
) throws -> Pad {
    var dict: [String: Any] = [
        "id": id,
        "title": title,
        "state": state,
        "owner_email": ownerEmail,
        "participants": participants
    ]
    if let language { dict["language"] = language }
    if let type { dict["type"] = type }
    if let teamName { dict["team"] = ["id": teamName, "name": teamName] }
    if let updatedAt { dict["updated_at"] = updatedAt }
    if let createdAt { dict["created_at"] = createdAt }
    if let isPrivate { dict["private"] = isPrivate }
    let data = try JSONSerialization.data(withJSONObject: dict)
    return try CoderPadClient.decoder.decode(Pad.self, from: data)
}

@Suite("Pad date range")
struct PadDateRangeTests {
    @Test
    func `today starts at midnight of the current day`() {
        let start = PadDateRange.start(for: "today", now: fixedNow, calendar: utcCalendar)
        #expect(start == ISO8601DateFormatter().date(from: "2026-06-12T00:00:00Z"))
    }

    @Test
    func `last 24 hours rolls back exactly one day from now`() {
        let start = PadDateRange.start(for: "last 24 hours", now: fixedNow, calendar: utcCalendar)
        #expect(start == ISO8601DateFormatter().date(from: "2026-06-11T12:00:00Z"))
    }

    @Test
    func `last 7 days anchors to midnight, today plus six prior days`() {
        let start = PadDateRange.start(for: "last 7 days", now: fixedNow, calendar: utcCalendar)
        #expect(start == ISO8601DateFormatter().date(from: "2026-06-06T00:00:00Z"))
    }

    @Test
    func `last 30 days anchors to midnight, today plus twenty-nine prior days`() {
        let start = PadDateRange.start(for: "last 30 days", now: fixedNow, calendar: utcCalendar)
        #expect(start == ISO8601DateFormatter().date(from: "2026-05-14T00:00:00Z"))
    }

    @Test
    func `last 90 days anchors to midnight, today plus eighty-nine prior days`() {
        let start = PadDateRange.start(for: "last 90 days", now: fixedNow, calendar: utcCalendar)
        #expect(start == ISO8601DateFormatter().date(from: "2026-03-15T00:00:00Z"))
    }

    @Test
    func `an unrecognized option imposes no lower bound`() {
        #expect(PadDateRange.start(for: "all time", now: fixedNow) == nil)
        #expect(PadDateRange.start(for: "", now: fixedNow) == nil)
    }

    @Test
    func `the chip options match the recognized keys`() {
        for option in PadDateRange.options {
            #expect(PadDateRange.start(for: option, now: fixedNow) != nil)
        }
    }
}

@Suite("Pad activity since open")
struct PadActivitySinceOpenTests {
    private func date(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string) ?? .distantPast
    }

    @Test
    func `started pad updated after last open shows the dot`() throws {
        let pad = try makePad(state: "started", updatedAt: "2026-06-12T12:00:00Z")
        #expect(PadListLogic.hasNewActivitySinceOpen(pad, lastOpened: date("2026-06-12T11:00:00Z")))
    }

    @Test
    func `started pad updated before last open shows no dot`() throws {
        let pad = try makePad(state: "started", updatedAt: "2026-06-12T10:00:00Z")
        #expect(!PadListLogic.hasNewActivitySinceOpen(pad, lastOpened: date("2026-06-12T11:00:00Z")))
    }

    @Test
    func `a never-opened pad shows no dot`() throws {
        let pad = try makePad(state: "started", updatedAt: "2026-06-12T12:00:00Z")
        #expect(!PadListLogic.hasNewActivitySinceOpen(pad, lastOpened: nil))
    }

    @Test
    func `a non-started pad shows no dot even with new activity`() throws {
        let pad = try makePad(state: "ended", updatedAt: "2026-06-12T12:00:00Z")
        #expect(!PadListLogic.hasNewActivitySinceOpen(pad, lastOpened: date("2026-06-12T11:00:00Z")))
    }

    @Test
    func `a started pad with no updated_at shows no dot`() throws {
        let pad = try makePad(state: "started")
        #expect(!PadListLogic.hasNewActivitySinceOpen(pad, lastOpened: date("2026-06-12T11:00:00Z")))
    }
}

@Suite("Pad refresh cadence")
struct PadRefreshIntervalTests {
    let base = Duration.seconds(90)

    @Test
    func `small list with a started pad uses the base cadence`() {
        #expect(PadListLogic.refreshInterval(base: base, padCount: 10, hasStartedPads: true) == base)
    }

    @Test
    func `no started pads backs off 2x`() {
        #expect(PadListLogic.refreshInterval(base: base, padCount: 10, hasStartedPads: false) == base * 2)
    }

    @Test
    func `large list compounds the size and no-started back-offs`() {
        #expect(PadListLogic.refreshInterval(base: base, padCount: 5000, hasStartedPads: false) == base * 8)
    }

    @Test
    func `medium list with started pads scales by size only`() {
        #expect(PadListLogic.refreshInterval(base: base, padCount: 1000, hasStartedPads: true) == base * 2)
    }
}

@Suite("Refresh schedule (wall-clock grid)")
struct RefreshScheduleTests {
    let clock = ContinuousClock()

    @Test
    func `fires one interval after the anchor when caught up`() {
        let anchor = clock.now
        let fire = RefreshSchedule.nextFire(after: anchor, interval: .seconds(10), now: anchor)
        #expect(fire == anchor.advanced(by: .seconds(10)))
    }

    @Test
    func `realigns to the next future boundary after a long gap, no burst`() {
        let anchor = clock.now
        // 25s elapsed since the anchor on a 10s grid: boundaries at +10 and +20 are
        // already past, so the next fire is the +30 boundary (not a catch-up burst).
        let now = anchor.advanced(by: .seconds(25))
        let fire = RefreshSchedule.nextFire(after: anchor, interval: .seconds(10), now: now)
        #expect(fire == anchor.advanced(by: .seconds(30)))
    }

    @Test
    func `next fire is always strictly in the future`() {
        let anchor = clock.now
        for elapsed in [0, 3, 9, 10, 11, 100] {
            let now = anchor.advanced(by: .seconds(elapsed))
            let fire = RefreshSchedule.nextFire(after: anchor, interval: .seconds(10), now: now)
            #expect(fire > now)
        }
    }

    @Test
    func `a non-positive interval still advances`() {
        let now = clock.now
        let fire = RefreshSchedule.nextFire(after: now, interval: .zero, now: now)
        #expect(fire > now)
    }
}

@Suite("Spotlight item identifiers")
struct SpotlightIndexerTests {
    @Test
    func `a pad identifier round-trips the pad id`() {
        #expect(SpotlightIndexer.padID(fromItemIdentifier: "pad:ABC123") == "ABC123")
        #expect(SpotlightIndexer.padID(fromItemIdentifier: "question:42") == nil)
    }

    @Test
    func `a question identifier is recognized`() {
        #expect(SpotlightIndexer.isQuestion(itemIdentifier: "question:42"))
        #expect(!SpotlightIndexer.isQuestion(itemIdentifier: "pad:ABC123"))
    }

    @Test
    func `a question identifier round-trips its account and id`() {
        let account = UUID()
        let identifier = "question:\(account.uuidString):42"
        let ref = SpotlightIndexer.questionRef(fromItemIdentifier: identifier)
        #expect(ref?.account == account)
        #expect(ref?.id == 42)
        // A pad identifier, or a legacy un-namespaced question id, isn't a valid ref.
        #expect(SpotlightIndexer.questionRef(fromItemIdentifier: "pad:ABC123") == nil)
        #expect(SpotlightIndexer.questionRef(fromItemIdentifier: "question:42") == nil)
    }
}

@Suite("Pad event grouping")
struct PadEventGroupingTests {
    private func event(_ kind: String, user: String?, at seconds: TimeInterval) -> PadEvent {
        PadEvent(message: "m", kind: kind, metadata: nil, userName: user,
                 userEmail: nil, createdAt: Date(timeIntervalSince1970: seconds))
    }

    @Test
    func `an empty log produces no groups`() {
        #expect(PadEventGrouping.group([]).isEmpty)
    }

    @Test
    func `consecutive same-kind, same-user events collapse into one group`() {
        let events = [
            event("typed", user: "Alex", at: 1),
            event("typed", user: "Alex", at: 2),
            event("typed", user: "Alex", at: 3)
        ]
        let groups = PadEventGrouping.group(events)
        #expect(groups.count == 1)
        #expect(groups[0].count == 3)
        // The representative is the first event; lastEvent is the most recent.
        #expect(groups[0].representative.createdAt == Date(timeIntervalSince1970: 1))
        #expect(groups[0].lastEvent.createdAt == Date(timeIntervalSince1970: 3))
    }

    @Test
    func `a different user breaks the run`() {
        let groups = PadEventGrouping.group([
            event("typed", user: "Alex", at: 1),
            event("typed", user: "Sam", at: 2)
        ])
        #expect(groups.count == 2)
        #expect(groups.allSatisfy { $0.count == 1 })
    }

    @Test
    func `a different kind breaks the run even when both kinds are collapsible`() {
        let groups = PadEventGrouping.group([
            event("typed", user: "Alex", at: 1),
            event("edited", user: "Alex", at: 2)
        ])
        #expect(groups.count == 2)
    }

    @Test
    func `non-collapsible kinds are never merged`() {
        // Two consecutive joins by the same user remain two distinct rows.
        let groups = PadEventGrouping.group([
            event("joined", user: "Alex", at: 1),
            event("joined", user: "Alex", at: 2)
        ])
        #expect(groups.count == 2)
    }

    @Test
    func `a collapsible run is bracketed by lifecycle events`() {
        let groups = PadEventGrouping.group([
            event("started", user: "Alex", at: 1),
            event("ran", user: "Alex", at: 2),
            event("ran", user: "Alex", at: 3),
            event("ended", user: "Alex", at: 4)
        ])
        // started (1) + collapsed ran×2 (1) + ended (1) = three groups.
        #expect(groups.map(\.count) == [1, 2, 1])
        #expect(groups.map(\.representative.kind) == ["started", "ran", "ended"])
    }
}

// Serialized: OrgDirectory.load reaches a mock client and the suite asserts on
// the resulting shared lookup; keeping it serial avoids interleaving loads.
@Suite("Org directory", .serialized)
struct OrgDirectoryTests {
    @Test
    func `display falls back to the email until a name is known`() {
        let directory = OrgDirectory()
        #expect(directory.name(for: "who@x.co") == nil)
        #expect(directory.display("who@x.co") == "who@x.co")
    }

    @Test
    func `name(for:) trims whitespace and rejects blanks`() {
        let directory = OrgDirectory()
        // No lookup is populated, so a blank email returns nil rather than a key hit.
        #expect(directory.name(for: "   ") == nil)
        #expect(directory.name(for: "") == nil)
    }

    @Test
    func `loading the demo org populates names and the default language`() async {
        let directory = OrgDirectory()
        await directory.load(for: .demo())
        #expect(directory.display(MockFixtures.demoUserEmail) == MockFixtures.demoUserName)
        // Trailing whitespace is trimmed before the lookup.
        #expect(directory.name(for: " \(MockFixtures.demoUserEmail) ") == MockFixtures.demoUserName)
        #expect(directory.defaultLanguage == "go")
    }

    @Test
    func `a failed load leaves the directory empty and unblocked for a later load`() async {
        let directory = OrgDirectory()
        // The bad-key account 401s, so nothing is cached and no account is marked loaded.
        await directory.load(for: .demoBadKey())
        #expect(directory.display(MockFixtures.demoUserEmail) == MockFixtures.demoUserEmail)
        #expect(directory.defaultLanguage == nil)
        // A subsequent successful load still populates rather than being skipped.
        await directory.load(for: .demo())
        #expect(directory.display(MockFixtures.demoUserEmail) == MockFixtures.demoUserName)
    }
}

@Suite("Multi-select primary")
struct MultiSelectLogicTests {
    @Test
    func `prefers the newly added row as the primary`() {
        #expect(MultiSelectLogic.primaryID(previous: ["a"], current: ["a", "b"]) == "b")
    }

    @Test
    func `falls back to a remaining row when none was added`() {
        // Deselecting "b" from {a,b} leaves {a}: nothing was added, so the sole
        // remaining row becomes the primary.
        #expect(MultiSelectLogic.primaryID(previous: ["a", "b"], current: ["a"]) == "a")
    }

    @Test
    func `is nil when the selection is cleared`() {
        #expect(MultiSelectLogic.primaryID(previous: ["a"], current: Set<String>()) == nil)
    }
}
