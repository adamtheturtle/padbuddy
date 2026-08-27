//
//  PadBuddyTests+FavoriteQuestionPersistence.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Favorite question persistence")
struct FavoriteQuestionPersistenceTests {
    @Test func `corrupt favorites are discarded for clean recovery`() throws {
        let suite = "FavoriteQuestionPersistenceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("not-json".utf8), forKey: "favorites")

        let decoded: [UUID: [FavoriteQuestion]]? = FavoriteQuestionsStore.decodePersisted(
            [UUID: [FavoriteQuestion]].self,
            key: "favorites",
            defaults: defaults
        )

        #expect(decoded == nil)
        #expect(defaults.object(forKey: "favorites") == nil)
    }
}
