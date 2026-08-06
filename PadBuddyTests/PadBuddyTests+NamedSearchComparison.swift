//
//  PadBuddyTests+NamedSearchComparison.swift
//  PadBuddyTests
//

@testable import PadBuddy
import Testing

@Suite("Named search filter comparison")
struct NamedSearchComparisonTests {
    @Test
    func `effective text and picker filters compare by their matching semantics`() {
        let saved = NamedSearch(
            name: "Saved",
            search: "  CAFÉ  ",
            languageFilter: " Swift ",
            ownerFilter: "Owner@Example.com",
            teamFilter: "Platform"
        )
        let live = NamedSearch(
            name: "Live",
            search: "cafe\u{301}",
            languageFilter: "swift",
            ownerFilter: "owner@example.COM",
            teamFilter: "platform"
        )

        #expect(saved.hasSameFilters(as: live))
    }

    @Test
    func `nil and empty optional filters remain distinct`() {
        let inactive = NamedSearch(name: "Inactive")
        let activeEmpty = NamedSearch(name: "Active", ownerFilter: "")

        #expect(!inactive.hasSameFilters(as: activeEmpty))
    }

    @Test
    func `controlled semantic filters still require exact values`() {
        let draft = NamedSearch(name: "Draft", draftFilter: "draft")
        let differentlyCased = NamedSearch(name: "Draft", draftFilter: "DRAFT")

        #expect(!draft.hasSameFilters(as: differentlyCased))
    }
}
