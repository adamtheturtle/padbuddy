//
//  PadBuddyTests+CompanionSearchQuery.swift
//  PadBuddyTests
//

@testable import PadBuddy
import Testing

@Suite("Companion search query")
struct CompanionSearchQueryTests {
    @Test func `query is bounded before matching retained rows`() {
        let query = boundedCompanionSearchInput(
            String(repeating: "x", count: maxCompanionSearchCharacters * 4)
        )

        #expect(query.count == maxCompanionSearchCharacters)
    }

    @Test func `live input preserves the trailing space needed for another word`() {
        #expect(boundedCompanionSearchInput("backend ") == "backend ")
        #expect(normalizedCompanionSearchQuery("backend ") == "backend")
    }
}
