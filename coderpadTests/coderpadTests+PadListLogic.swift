//
//  coderpadTests+PadListLogic.swift
//  coderpadTests
//

@testable import CoderPad
import Foundation
import Testing

// MARK: - Pad list logic (filters, date ranges)

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

    @Test
    func `a negative count backs off instead of polling fastest`() {
        #expect(PadListLogic.refreshInterval(base: base, padCount: -1, hasStartedPads: true) == base * 4)
        #expect(PadListLogic.refreshInterval(base: base, padCount: -1, hasStartedPads: false) == base * 8)
    }

    @Test
    func `an empty list still uses the base cadence`() {
        #expect(PadListLogic.refreshInterval(base: base, padCount: 0, hasStartedPads: true) == base)
    }
}

@Suite("Automatic refresh backoff")
struct AutoRefreshPolicyTests {
    let base = Duration.seconds(90)

    @Test func `success uses the baseline without jitter`() {
        #expect(AutoRefreshPolicy.interval(base: base, consecutiveFailures: 0, jitter: 0) == base)
    }

    @Test func `failures back off exponentially and cap at 32x`() {
        #expect(AutoRefreshPolicy.interval(base: base, consecutiveFailures: 1, jitter: 0) == base * 2)
        #expect(AutoRefreshPolicy.interval(base: base, consecutiveFailures: 4, jitter: 0) == base * 16)
        #expect(AutoRefreshPolicy.interval(base: base, consecutiveFailures: 99, jitter: 0) == base * 32)
    }

    @Test func `jitter is bounded to ten percent`() {
        #expect(AutoRefreshPolicy.interval(base: base, consecutiveFailures: 0, jitter: -99) == base * 0.9)
        #expect(AutoRefreshPolicy.interval(base: base, consecutiveFailures: 0, jitter: 99) == base * 1.1)
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

@Suite("Pad history replay")
struct PadHistoryReplayTests {
    @Test
    func `file history precomputes one snapshot per edit`() {
        let history = PadHistory(entries: [
            PadHistoryEntry(id: "a", author: "Basil", operations: [.insert("h")], timestamp: 1),
            PadHistoryEntry(id: "b", author: "Basil", operations: [.retain(1), .insert("i")], timestamp: 2),
            PadHistoryEntry(id: "c", author: "Sybil", operations: [.retain(2), .insert("!")], timestamp: 3)
        ])

        let file = PadFileHistory(id: "history-url", title: "main.py", language: "python", history: history)

        #expect(file.snapshots.indices.compactMap(file.contents(at:)) == ["h", "hi", "hi!"])
        #expect(file.snapshots.map(\.index) == [0, 1, 2])
        #expect(file.latestEntry?.id == "c")
    }

    @Test
    func `repeated entry IDs still produce unique snapshot identities`() {
        let history = PadHistory(entries: [
            PadHistoryEntry(id: "retry", author: "Basil", operations: [.insert("a")], timestamp: 1),
            PadHistoryEntry(id: "retry", author: "Basil", operations: [.retain(1), .insert("b")], timestamp: 2)
        ])

        let file = PadFileHistory(id: "history-url", title: "main.py", language: "python", history: history)

        #expect(file.snapshots.map(\.id) == ["0-retry", "1-retry"])
        #expect(Set(file.snapshots.map(\.id)).count == file.snapshots.count)
    }

    @Test
    func `snapshots record the line their edit lands on`() {
        let history = PadHistory(entries: [
            PadHistoryEntry(id: "a", author: "Basil", operations: [.insert("a\nb\nc")], timestamp: 1),
            // Retain past both newlines (4 UTF-16 units: a, newline, b, newline),
            // then insert on the third line.
            PadHistoryEntry(id: "b", author: "Basil", operations: [.retain(4), .insert("X")], timestamp: 2)
        ])

        let file = PadFileHistory(id: "history-url", title: "main.py", language: "python", history: history)

        #expect(file.snapshots.indices.compactMap(file.contents(at:)) == ["a\nb\nc", "a\nb\nXc"])
        #expect(file.snapshots.map(\.changeLine) == [0, 2])
        #expect(file.snapshots.map(\.cursorOffset) == [5, 5])
        #expect(file.snapshots.map(\.cursorLine) == [2, 2])
    }

    @Test
    func `snapshot cursor follows insertions and rests at deletion start`() {
        let history = PadHistory(entries: [
            PadHistoryEntry(id: "seed", author: "Basil", operations: [.insert("abc")], timestamp: 1),
            PadHistoryEntry(
                id: "replace", author: "Basil",
                operations: [.retain(1), .delete(1), .insert("XY"), .retain(1)], timestamp: 2
            ),
            PadHistoryEntry(
                id: "delete", author: "Basil",
                operations: [.retain(2), .delete(1), .retain(1)], timestamp: 3
            )
        ])

        let file = PadFileHistory(
            id: "history-url", title: "main.py", language: "python", history: history
        )

        #expect(file.snapshots.indices.compactMap(file.contents(at:)) == ["abc", "aXYc", "aXc"])
        #expect(file.snapshots.map(\.cursorOffset) == [3, 3, 2])
    }

    @Test
    func `history retains periodic document checkpoints instead of every snapshot`() {
        let entries = (0 ..< 300).map { index in
            PadHistoryEntry(
                id: "\(index)", author: "Basil",
                operations: [.retain(index), .insert("x")], timestamp: Int64(index)
            )
        }
        let file = PadFileHistory(
            id: "history-url", title: "main.py", language: "python", history: PadHistory(entries: entries)
        )

        #expect(file.contents(at: 127) == String(repeating: "x", count: 128))
        #expect(file.contents(at: 299) == String(repeating: "x", count: 300))
        #expect(file.retainedSnapshotContentBytes < 1000)
    }

    @Test
    func `malformed retain offsets are clamped to the document`() {
        let history = PadHistory(entries: [
            PadHistoryEntry(id: "seed", author: "Basil", operations: [.insert("a\nb")], timestamp: 1),
            PadHistoryEntry(
                id: "oversized",
                author: "Basil",
                operations: [.retain(.max), .retain(.max), .insert("x")],
                timestamp: 2
            ),
            PadHistoryEntry(id: "negative", author: "Basil", operations: [.retain(-10), .insert("y")], timestamp: 3)
        ])

        let file = PadFileHistory(id: "history-url", title: "main.py", language: "python", history: history)

        #expect(file.snapshots.map(\.changeLine) == [0, 1, 0])
        #expect(file.snapshots.map(\.cursorOffset) == [3, 4, 1])
    }
}

// Serialized: OrgDirectory.load reaches a mock client and the suite asserts on
// the resulting shared lookup; keeping it serial avoids interleaving loads.
@Suite("Org directory", .serialized)
struct OrgDirectoryTests {
    @Test
    func `display falls back to the email until a name is known`() {
        let directory = OrgDirectory(seedFromDisk: false)
        #expect(directory.name(for: "who@x.co") == nil)
        #expect(directory.display("who@x.co") == "who@x.co")
    }

    @Test
    func `name(for:) trims whitespace and rejects blanks`() {
        let directory = OrgDirectory(seedFromDisk: false)
        // No lookup is populated, so a blank email returns nil rather than a key hit.
        #expect(directory.name(for: "   ") == nil)
        #expect(directory.name(for: "") == nil)
    }

    @Test
    func `loading the demo org populates names and the default language`() async {
        let directory = OrgDirectory(seedFromDisk: false)
        await directory.load(for: .demo())
        #expect(directory.display(MockFixtures.demoUserEmail) == MockFixtures.demoUserName)
        // Trailing whitespace is trimmed before the lookup.
        #expect(directory.name(for: " \(MockFixtures.demoUserEmail) ") == MockFixtures.demoUserName)
        #expect(directory.defaultLanguage == "go")
    }

    @Test
    func `a failed load leaves the directory empty and unblocked for a later load`() async {
        let directory = OrgDirectory(seedFromDisk: false)
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
