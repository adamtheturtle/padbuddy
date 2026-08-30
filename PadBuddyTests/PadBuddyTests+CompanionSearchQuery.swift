//
//  PadBuddyTests+CompanionSearchQuery.swift
//  PadBuddyTests
//

@testable import PadBuddy
import Testing

@Suite("Companion search query")
struct CompanionSearchQueryTests {
    @Test func `query is bounded before matching retained rows`() {
        let query = normalizedCompanionSearchQuery(
            String(repeating: "x", count: maxCompanionSearchCharacters * 4)
        )

        #expect(query.count == maxCompanionSearchCharacters)
    }
}
