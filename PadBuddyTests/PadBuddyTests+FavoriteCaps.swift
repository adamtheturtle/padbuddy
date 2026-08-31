//
//  PadBuddyTests+FavoriteCaps.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Favorite entry caps")
struct FavoriteCapsTests {
    @Test func `pad titles are bounded at capture, not only on decode`() {
        let long = String(repeating: "a", count: FavoritePadsStore.maxTitleLength + 40)
        let bounded = FavoritePadsStore.boundedTitle(long)

        #expect(bounded.count == FavoritePadsStore.maxTitleLength)
        #expect(long.hasPrefix(bounded))
    }

    @Test func `question titles are bounded at capture, not only on decode`() {
        let long = String(repeating: "b", count: FavoriteQuestionsStore.maxTitleLength + 40)
        let bounded = FavoriteQuestionsStore.boundedTitle(long)

        #expect(bounded.count == FavoriteQuestionsStore.maxTitleLength)
        #expect(long.hasPrefix(bounded))
    }

    @Test func `a title already within the cap is left alone`() {
        #expect(FavoritePadsStore.boundedTitle("Interview pad") == "Interview pad")
        #expect(FavoriteQuestionsStore.boundedTitle("Two Sum") == "Two Sum")
    }

    /// The message the caps show once an account is full. It has to name the cap it
    /// hit, since silently refusing the star is what #4788 was about.
    @Test func `the limit message names the cap`() {
        #expect(FavoritePadsStore.limitReachedMessage
            .contains("\(FavoritePadsStore.maxEntriesPerAccount)"))
        #expect(FavoriteQuestionsStore.limitReachedMessage
            .contains("\(FavoriteQuestionsStore.maxEntriesPerAccount)"))
    }

    @Test func `decoded pad entries are clamped to the entry cap`() {
        let over = (0 ..< (FavoritePadsStore.maxEntriesPerAccount + 25)).map {
            FavoritePad(id: "pad-\($0)", title: "t", addedAt: nil)
        }

        let sanitized = FavoritePadsStore.sanitized(over)

        #expect(sanitized.count == FavoritePadsStore.maxEntriesPerAccount)
        // The prefix is kept, so the order the user arranged survives the clamp.
        #expect(sanitized.first?.id == "pad-0")
    }

    /// The legacy id-only blob used to bypass `sanitized` entirely (#4787), so a
    /// duplicated or over-long v1 blob was carried into v2 unclamped.
    @Test func `decoded question entries are de-duplicated and clamped`() {
        let over = (0 ..< (FavoriteQuestionsStore.maxEntriesPerAccount + 10)).map {
            FavoriteQuestion(id: $0, title: "")
        }

        let sanitized = FavoriteQuestionsStore.sanitized(over + [FavoriteQuestion(id: 0, title: "")])

        #expect(sanitized.count == FavoriteQuestionsStore.maxEntriesPerAccount)
        #expect(Set(sanitized.map(\.id)).count == sanitized.count)
    }
}

@Suite("Favorite pad title mutation stability", .serialized)
@MainActor
struct FavoritePadTitleMutationStabilityTests {
    private let store = FavoritePadsStore.shared

    @Test func `refreshing an unchanged bounded long title does not save`() {
        let account = UUID()
        let longTitle = String(repeating: "r", count: FavoritePadsStore.maxTitleLength + 40)
        store.byAccount[account] = [FavoritePad(
            id: "long-refresh", title: FavoritePadsStore.boundedTitle(longTitle), addedAt: nil
        )]
        defer { store.byAccount[account] = nil }
        let revision = store.revision

        store.refreshTitles(from: [Pad(id: "long-refresh", title: longTitle)], account: account)

        #expect(store.revision == revision)
    }

    @Test func `readding an unchanged bounded long title does not save`() {
        let account = UUID()
        let longTitle = String(repeating: "a", count: FavoritePadsStore.maxTitleLength + 40)
        store.byAccount[account] = [FavoritePad(
            id: "long-add", title: FavoritePadsStore.boundedTitle(longTitle), addedAt: nil
        )]
        defer { store.byAccount[account] = nil }
        let revision = store.revision

        store.add("long-add", title: longTitle, account: account)

        #expect(store.revision == revision)
    }
}
