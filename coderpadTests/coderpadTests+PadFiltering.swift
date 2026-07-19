//
//  coderpadTests+PadFiltering.swift
//  coderpadTests
//

@testable import CoderPad
import Foundation
import Testing

/// A fixed clock so the date-range filters don't depend on the wall clock.
private let fixedNow = ISO8601DateFormatter().date(from: "2026-06-12T12:00:00Z") ?? .distantPast

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

@Suite("Pad filtering")
struct PadFilterTests {
    private func samplePads() throws -> [Pad] {
        try [
            makePad(id: "ABC1", title: "Onsite", state: "started",
                    ownerEmail: "alex@demo.co", language: "python3", type: "live",
                    teamName: "Cursor", participants: ["Jane Doe"],
                    updatedAt: "2026-06-11T09:00:00Z"),
            makePad(id: "XYZ2", title: "Take Home Challenge", state: "ended",
                    ownerEmail: "sam@demo.co", language: "go", type: "take-home",
                    teamName: nil, participants: [],
                    updatedAt: "2026-01-01T09:00:00Z")
        ]
    }

    @Test
    func `empty criteria returns every pad`() throws {
        let pads = try samplePads()
        let result = PadListLogic.filter(pads, using: PadFilterCriteria())
        #expect(result.map(\.id) == ["ABC1", "XYZ2"])
    }

    @Test
    func `state filter keeps only matching pads`() throws {
        let result = try PadListLogic.filter(samplePads(),
                                             using: PadFilterCriteria(state: .active))
        #expect(result.map(\.id) == ["ABC1"])
    }

    @Test
    func `language filter is case-insensitive`() throws {
        let pads = try samplePads()
        #expect(PadListLogic.filter(pads, using: PadFilterCriteria(language: "python3")).map(\.id) == ["ABC1"])
        // An upper-cased criterion still matches the lower-cased pad language.
        #expect(PadListLogic.filter(pads, using: PadFilterCriteria(language: "PYTHON3")).map(\.id) == ["ABC1"])
    }

    @Test
    func `owner and team filters match exactly`() throws {
        let pads = try samplePads()
        #expect(PadListLogic.filter(pads, using: PadFilterCriteria(owner: "sam@demo.co")).map(\.id) == ["XYZ2"])
        #expect(PadListLogic.filter(pads, using: PadFilterCriteria(team: "Cursor")).map(\.id) == ["ABC1"])
    }

    /// Emails are case-insensitive: the Me shortcut or a persisted filter can
    /// carry a different casing than the API's owner values (#1643).
    @Test
    func `owner filter ignores email casing`() throws {
        let pads = try samplePads()
        #expect(PadListLogic.filter(pads, using: PadFilterCriteria(owner: "Sam@Demo.CO")).map(\.id) == ["XYZ2"])
    }

    @Test
    func `interview-type filter keeps only the matching type`() throws {
        let pads = try samplePads()
        #expect(PadListLogic.filter(pads, using: PadFilterCriteria(type: "take-home")).map(\.id) == ["XYZ2"])
        #expect(PadListLogic.filter(pads, using: PadFilterCriteria(type: "live")).map(\.id) == ["ABC1"])
    }

    @Test
    func `search matches title, id, owner email, and participants`() throws {
        let pads = try samplePads()
        #expect(PadListLogic.filter(pads, using: PadFilterCriteria(search: "onsite")).map(\.id) == ["ABC1"])
        #expect(PadListLogic.filter(pads, using: PadFilterCriteria(search: "abc1")).map(\.id) == ["ABC1"])
        #expect(PadListLogic.filter(pads, using: PadFilterCriteria(search: "sam@")).map(\.id) == ["XYZ2"])
        #expect(PadListLogic.filter(pads, using: PadFilterCriteria(search: "jane")).map(\.id) == ["ABC1"])
        let noMatches = PadListLogic.filter(pads, using: PadFilterCriteria(search: "nothinghere"))
        #expect(noMatches.isEmpty)
    }

    @Test
    func `whitespace-only search behaves like empty search`() throws {
        let pads = try samplePads()
        let unsearched = PadListLogic.filter(pads, using: PadFilterCriteria()).map(\.id)
        let whitespace = PadListLogic.filter(pads, using: PadFilterCriteria(search: " \n\t ")).map(\.id)
        #expect(whitespace == unsearched)
    }

    @Test
    func `search also matches the directory-resolved owner display name`() throws {
        let pads = try samplePads()
        let display: (String) -> String = { $0 == "alex@demo.co" ? "Alex Park" : $0 }
        // "Alex Park" appears nowhere in the raw pad, only via the directory.
        let result = PadListLogic.filter(pads, using: PadFilterCriteria(search: "alex park"), display: display)
        #expect(result.map(\.id) == ["ABC1"])
    }

    @Test
    func `filters combine with AND`() throws {
        let pads = try samplePads()
        // Active pads that are written in Go: none, since the only Go pad is ended.
        let result = PadListLogic.filter(pads, using: PadFilterCriteria(state: .active, language: "go"))
        #expect(result.isEmpty)
    }

    @Test
    func `date-range filter keeps pads updated within the window`() throws {
        let pads = try samplePads()
        // ABC1 was updated yesterday, XYZ2 back in January.
        let recent = PadListLogic.filter(
            pads, using: PadFilterCriteria(updated: DateWindow(range: "last 7 days")), now: fixedNow
        )
        #expect(recent.map(\.id) == ["ABC1"])
        let month = PadListLogic.filter(
            pads, using: PadFilterCriteria(updated: DateWindow(range: "last 30 days")), now: fixedNow
        )
        #expect(month.map(\.id) == ["ABC1"])
    }

    @Test
    func `date filter cache token advances with the clock only while active`() {
        let minuteStart = Date(timeIntervalSinceReferenceDate: 3600)
        let sameMinute = Date(timeIntervalSinceReferenceDate: 3659)
        let nextMinute = Date(timeIntervalSinceReferenceDate: 3660)

        let inactiveToken = PadListLogic.dateFilterCacheToken(
            updated: DateWindow(),
            created: DateWindow(),
            now: minuteStart
        )
        #expect(inactiveToken == nil)
        #expect(PadListLogic.dateFilterCacheToken(
            updated: DateWindow(range: "today"),
            created: DateWindow(),
            now: minuteStart
        ) == PadListLogic.dateFilterCacheToken(
            updated: DateWindow(range: "today"),
            created: DateWindow(),
            now: sameMinute
        ))
        #expect(PadListLogic.dateFilterCacheToken(
            updated: DateWindow(range: "today"),
            created: DateWindow(),
            now: minuteStart
        ) != PadListLogic.dateFilterCacheToken(
            updated: DateWindow(range: "today"),
            created: DateWindow(),
            now: nextMinute
        ))
    }

    @Test
    func `the created window compares against created_at, not updated_at`() throws {
        // OLD was created in January but bumped (updated) yesterday; NEW is the
        // reverse. An updated window keeps OLD; a created window keeps NEW.
        let pads = try [
            makePad(id: "OLD", updatedAt: "2026-06-11T09:00:00Z", createdAt: "2026-01-01T09:00:00Z"),
            makePad(id: "NEW", updatedAt: "2026-01-02T09:00:00Z", createdAt: "2026-06-11T09:00:00Z")
        ]
        let byUpdated = PadListLogic.filter(
            pads, using: PadFilterCriteria(updated: DateWindow(range: "last 7 days")), now: fixedNow
        )
        #expect(byUpdated.map(\.id) == ["OLD"])
        let byCreated = PadListLogic.filter(
            pads, using: PadFilterCriteria(created: DateWindow(range: "last 7 days")), now: fixedNow
        )
        #expect(byCreated.map(\.id) == ["NEW"])
    }

    @Test
    func `a custom range bounds a window on both ends and overrides its named window`() throws {
        let iso = ISO8601DateFormatter()
        let pads = try [
            makePad(id: "MAR", updatedAt: "2026-03-15T12:00:00Z"),
            makePad(id: "APR", updatedAt: "2026-04-15T12:00:00Z"),
            makePad(id: "MAY", updatedAt: "2026-05-15T12:00:00Z")
        ]
        // April only. The named window is set too, to prove custom takes precedence.
        let criteria = PadFilterCriteria(updated: DateWindow(
            range: "last 7 days",
            customStart: iso.date(from: "2026-04-01T00:00:00Z"),
            customEnd: iso.date(from: "2026-04-30T23:59:59Z")
        ))
        #expect(PadListLogic.filter(pads, using: criteria, now: fixedNow).map(\.id) == ["APR"])
    }

    @Test
    func `the updated and created windows both apply at once`() throws {
        let iso = ISO8601DateFormatter()
        // Created in April, updated in June.
        let pads = try [
            makePad(id: "P", updatedAt: "2026-06-11T09:00:00Z", createdAt: "2026-04-15T09:00:00Z")
        ]
        // Updated within the last week AND created in April: both match.
        let both = PadFilterCriteria(
            updated: DateWindow(range: "last 7 days"),
            created: DateWindow(
                customStart: iso.date(from: "2026-04-01T00:00:00Z"),
                customEnd: iso.date(from: "2026-04-30T23:59:59Z")
            )
        )
        #expect(PadListLogic.filter(pads, using: both, now: fixedNow).map(\.id) == ["P"])
        // The created window (today only) excludes it even though the updated one matches.
        let mismatch = PadFilterCriteria(
            updated: DateWindow(range: "last 7 days"),
            created: DateWindow(range: "today")
        )
        let mismatched = PadListLogic.filter(pads, using: mismatch, now: fixedNow)
        #expect(mismatched.isEmpty)
    }

    /// `filter` is defined as `pads.filter(matches:)`, and the combined "All
    /// Accounts" list filters its account-tagged rows one at a time through
    /// `matches` directly. This locks the two to agree so the merged list can never
    /// drift from the single-account list's filtering.
    @Test
    func `matches agrees with filter for every pad and criteria`() throws {
        let pads = try samplePads()
        let criteriaSet = [
            PadFilterCriteria(),
            PadFilterCriteria(state: .active),
            PadFilterCriteria(language: "PYTHON3"),
            PadFilterCriteria(owner: "sam@demo.co"),
            PadFilterCriteria(team: "Cursor"),
            PadFilterCriteria(type: "take-home"),
            PadFilterCriteria(search: "onsite"),
            PadFilterCriteria(updated: DateWindow(range: "last 7 days"))
        ]
        for criteria in criteriaSet {
            let viaFilter = PadListLogic.filter(pads, using: criteria, now: fixedNow).map(\.id)
            let viaMatches = pads
                .filter { PadListLogic.matches($0, criteria: criteria, now: fixedNow) }
                .map(\.id)
            #expect(viaFilter == viaMatches)
        }
    }
}

@Suite("Question display title (#2493)")
struct QuestionDisplayTitleTests {
    private func question(id: Int, title: String) throws -> Question {
        let data = try JSONSerialization.data(withJSONObject: ["id": id, "title": title])
        return try CoderPadClient.decoder.decode(Question.self, from: data)
    }

    @Test
    func `a whitespace-only title falls back to the id label`() throws {
        // Only an exactly-empty title used to fall back, so a whitespace-only one
        // rendered as a blank row and sorted under a blank key (#2493).
        #expect(try question(id: 7, title: "   ").displayTitle == "#7")
        #expect(try question(id: 7, title: "\n\t").displayTitle == "#7")
        #expect(try question(id: 7, title: "").displayTitle == "#7")
    }

    @Test
    func `a real title is trimmed but kept`() throws {
        #expect(try question(id: 7, title: "  Binary Search  ").displayTitle == "Binary Search")
        #expect(try question(id: 7, title: "Binary Search").displayTitle == "Binary Search")
    }
}

@Suite("Widget favourite title lookup (#2139)")
struct WidgetFavoriteTitleLookupTests {
    private func question(id: Int, title: String) throws -> Question {
        let data = try JSONSerialization.data(withJSONObject: ["id": id, "title": title])
        return try CoderPadClient.decoder.decode(Question.self, from: data)
    }

    @Test
    func `only the favourited questions are titled`() throws {
        let questions = try [question(id: 1, title: "One"),
                             question(id: 2, title: "Two"),
                             question(id: 3, title: "Three")]
        let titles = WidgetSync.titles(forFavorites: [1, 3], in: questions)
        #expect(titles == [1: "One", 3: "Three"])
    }

    @Test
    func `the first entry for a repeated id wins`() throws {
        // Matches the uniquing the dictionary build used to do, so a duplicated
        // cache entry can't flip the widget's title (#2139).
        let questions = try [question(id: 1, title: "One"), question(id: 1, title: "Other")]
        #expect(WidgetSync.titles(forFavorites: [1], in: questions) == [1: "One"])
    }

    @Test
    func `no favourites means no lookup`() throws {
        let questions = try [question(id: 1, title: "One")]
        #expect(WidgetSync.titles(forFavorites: [], in: questions).isEmpty)
        #expect(WidgetSync.titles(forFavorites: [9], in: questions).isEmpty)
    }
}

@Suite("Pad sort edge cases (#2481, #2482)")
struct PadSortEdgeCaseTests {
    private func pad(id: String, title: String = "Pad", updatedAt: String? = nil) throws -> Pad {
        var dict: [String: Any] = [
            "id": id, "title": title, "state": "started", "owner_email": "", "participants": []
        ]
        if let updatedAt { dict["updated_at"] = updatedAt }
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try CoderPadClient.decoder.decode(Pad.self, from: data)
    }

    @Test
    func `a whitespace-only title sorts under the pad id`() throws {
        // "   " used to sort as a blank string, ahead of everything (#2481). Falling
        // back to the id puts it where the list actually shows it.
        let blank = try pad(id: "zzz", title: "   ")
        let alpha = try pad(id: "aaa", title: "Alpha")
        #expect(PadSort.titleAsc.sorted([blank, alpha]).map(\.id) == ["aaa", "zzz"])
    }

    @Test
    func `undated pads sort last in both directions`() throws {
        // Substituting .distantPast put undated pads among the oldest, which floated
        // them to the very top of an ascending sort (#2482).
        let dated = try pad(id: "dated", updatedAt: "2026-01-01T00:00:00Z")
        let undated = try pad(id: "undated")

        #expect(PadSort.updatedDesc.sorted([undated, dated]).map(\.id) == ["dated", "undated"])
        #expect(PadSort.updatedAsc.sorted([undated, dated]).map(\.id) == ["dated", "undated"])
    }

    @Test
    func `two undated pads still order deterministically`() throws {
        let first = try pad(id: "aaa")
        let second = try pad(id: "bbb")
        #expect(PadSort.updatedDesc.sorted([second, first]).map(\.id) == ["aaa", "bbb"])
    }
}
