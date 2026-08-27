//
//  PadBuddyTests+MergedFilters.swift
//  PadBuddyTests
//
//  The merged lists' persisted live-filter envelope (#913): account and preset
//  filters must survive the round-trip, and snapshots persisted by earlier builds
//  (a bare NamedSearch) must still restore.
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Merged filter snapshot (#913)")
struct MergedFilterSnapshotTests {
    @Test
    func `account and preset filters survive the round-trip`() throws {
        let account = UUID()
        let original = MergedFilterSnapshot(
            search: NamedSearch(name: "", search: "graphs", languageFilter: "python3",
                                ownerFilter: nil, typeFilter: nil, draftFilter: nil),
            accountFilter: account, mineOnly: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MergedFilterSnapshot.self, from: data)
        #expect(decoded.search.search == "graphs")
        #expect(decoded.accountFilter == account)
        #expect(decoded.mineOnly)
        #expect(!decoded.favoritesOnly)
    }

    @Test
    func `the two presets are mutually exclusive`() {
        // Each toolbar toggle turns the other off, so both being set can only come
        // from corrupt state or an older build. Restoring both constrained the list
        // to "mine AND favorited" — usually empty, with no clue why (#2574).
        let search = NamedSearch(name: "", search: "", languageFilter: nil,
                                 ownerFilter: nil, typeFilter: nil, draftFilter: nil)
        let both = MergedFilterSnapshot(search: search, mineOnly: true, favoritesOnly: true)
        #expect(!both.mineOnly)
        #expect(both.favoritesOnly)

        // Either one alone is untouched.
        #expect(MergedFilterSnapshot(search: search, mineOnly: true).mineOnly)
        #expect(MergedFilterSnapshot(search: search, favoritesOnly: true).favoritesOnly)
    }

    @Test
    func `the shared coder persists filters in the format a fresh one wrote (#2104)`() throws {
        // The single-account list now saves and restores its live filters through
        // `SharedCoders` instead of allocating a coder per filter change, so a
        // snapshot written by an older build must still restore — and one written
        // now must stay readable by a plain decoder.
        let search = NamedSearch(name: "", search: "graphs", languageFilter: "python3",
                                 ownerFilter: nil, typeFilter: nil, draftFilter: nil)

        let shared = try SharedCoders.encoder.encode(search)
        let plainlyRestored = try JSONDecoder().decode(NamedSearch.self, from: shared)
        #expect(plainlyRestored.search == "graphs")
        #expect(plainlyRestored.languageFilter == "python3")

        let legacy = try JSONEncoder().encode(search)
        let sharedRestored = try SharedCoders.decoder.decode(NamedSearch.self, from: legacy)
        #expect(sharedRestored.search == "graphs")
        #expect(sharedRestored.languageFilter == "python3")
    }

    @Test
    func `a snapshot decoded with both presets set keeps only favorites`() throws {
        let search = NamedSearch(name: "", search: "s", languageFilter: nil,
                                 ownerFilter: nil, typeFilter: nil, draftFilter: nil)
        let searchJSON = try #require(String(bytes: JSONEncoder().encode(search), encoding: .utf8))
        let json = #"{"search":\#(searchJSON),"mineOnly":true,"favoritesOnly":true}"#
        let decoded = try JSONDecoder().decode(MergedFilterSnapshot.self, from: Data(json.utf8))
        #expect(!decoded.mineOnly)
        #expect(decoded.favoritesOnly)
    }

    @Test
    func `a snapshot without preset keys decodes with them off`() throws {
        let search = NamedSearch(name: "", search: "s", languageFilter: nil,
                                 ownerFilter: nil, typeFilter: nil, draftFilter: nil)
        let searchJSON = try #require(String(bytes: JSONEncoder().encode(search), encoding: .utf8))
        let json = #"{"search":\#(searchJSON)}"#
        let decoded = try JSONDecoder().decode(MergedFilterSnapshot.self, from: Data(json.utf8))
        #expect(decoded.accountFilter == nil)
        #expect(!decoded.mineOnly)
        #expect(!decoded.favoritesOnly)
    }

    @Test
    func `a legacy bare NamedSearch blob is not mistaken for an envelope`() throws {
        // restoreFilters() tries the envelope first and falls back to NamedSearch;
        // a legacy blob must fail the envelope decode so the fallback runs.
        let legacy = NamedSearch(name: "", search: "s", languageFilter: nil,
                                 ownerFilter: nil, typeFilter: nil, draftFilter: nil)
        let data = try JSONEncoder().encode(legacy)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(MergedFilterSnapshot.self, from: data)
        }
        #expect(throws: Never.self) {
            try JSONDecoder().decode(NamedSearch.self, from: data)
        }
    }
}

@Suite("Named search name limit (#2555, #2556)")
struct NamedSearchNameLimitTests {
    @Test
    func `an oversized name is clamped by the initializer`() {
        let long = String(repeating: "a", count: NamedSearch.maxNameLength + 25)
        #expect(NamedSearch(name: long).name.count == NamedSearch.maxNameLength)
        // A name already inside the cap is untouched.
        #expect(NamedSearch(name: "Onsites").name == "Onsites")
    }

    @Test
    func `an oversized persisted name is clamped on decode`() throws {
        // A legacy or corrupt defaults entry would otherwise reintroduce a name the
        // initializer refuses, since Codable synthesis bypassed it entirely (#2556).
        let long = String(repeating: "b", count: 200)
        let json = #"{"id":"\#(UUID().uuidString)","name":"\#(long)","search":""}"#
        let decoded = try JSONDecoder().decode(NamedSearch.self, from: Data(json.utf8))
        #expect(decoded.name.count == NamedSearch.maxNameLength)
    }

    @Test
    func `clamping counts characters, not bytes`() {
        // Truncating by UTF-8 length would cut a multi-scalar emoji mid-sequence.
        let emoji = String(repeating: "👩‍💻", count: NamedSearch.maxNameLength + 5)
        #expect(NamedSearch(name: emoji).name.count == NamedSearch.maxNameLength)
    }
}

@Suite("Filter normalization")
struct FilterNormalizationTests {
    @Test
    func `option lists trim normalize deduplicate and locale-sort`() {
        #expect(FilterOptionValues.languages([" Swift ", "swift", " GO ", nil, "   "]) == ["go", "swift"])
        #expect(FilterOptionValues.owners([
            " User@Example.com ", "user@example.COM", " ada@example.com ", "\n"
        ]) == ["ada@example.com", "user@example.com"])
    }

    @Test
    func `question filter comparisons match padded API values`() {
        #expect(FilterOptionValues.language(" Swift ", matches: "swift"))
        #expect(FilterOptionValues.owner(" User@Example.com ", matches: "user@example.com"))
    }

    @Test
    func `pad filters match normalized API values`() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "id": "PADDED", "state": "started", "owner_email": " User@Example.com ",
            "language": " Swift ", "team": ["id": "team", "name": " Engineering "]
        ])
        let pad = try CoderPadClient.decoder.decode(Pad.self, from: data)

        #expect(PadListLogic.matches(pad, criteria: PadFilterCriteria(language: "swift")))
        #expect(PadListLogic.matches(pad, criteria: PadFilterCriteria(owner: "user@example.com")))
        #expect(PadListLogic.matches(pad, criteria: PadFilterCriteria(team: "Engineering")))
    }
}

@Suite("Merged account options")
@MainActor
struct MergedAccountOptionsCacheTests {
    @Test
    func `duplicate mergeable IDs keep the first option only`() {
        let id = UUID()
        let first = Account(name: "First", apiKey: "a", id: id, userEmail: "a@example.com")
        let duplicate = Account(name: "Duplicate", apiKey: "b", id: id, userEmail: "b@example.com")
        let other = Account(name: "Other", apiKey: "c", userEmail: "c@example.com")
        let cache = MergedAccountOptionsCache()

        cache.refresh([first, duplicate, other], mergeable: [first, duplicate, other])

        #expect(cache.ids == [id, other.id])
        #expect(cache.names[id] == "First")
        #expect(cache.names[other.id] == "Other")
    }
}
