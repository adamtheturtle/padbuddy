//
//  coderpadTests+FavoriteQuestionRefresh.swift
//  coderpadTests
//

@testable import CoderPad
import Testing

struct FavoriteQuestionRefreshTests {
    @Test
    func `authoritative refresh renames survivors and removes missing favorites`() {
        let entries = [
            FavoriteQuestion(id: 1, title: "Old", addedAt: nil),
            FavoriteQuestion(id: 2, title: "Deleted", addedAt: nil),
            FavoriteQuestion(id: 3, title: "Same", addedAt: nil)
        ]

        let result = FavoriteQuestionRefresh.reconcile(
            entries,
            authoritativeTitles: [1: "Renamed", 3: "Same"]
        )

        #expect(result.entries.map(\.id) == [1, 3])
        #expect(result.entries.map(\.title) == ["Renamed", "Same"])
        #expect(result.removedIDs == [2])
    }

    @Test
    func `empty authoritative refresh removes every favorite in order`() {
        let entries = [
            FavoriteQuestion(id: 4, title: "Four", addedAt: nil),
            FavoriteQuestion(id: 9, title: "Nine", addedAt: nil)
        ]

        let result = FavoriteQuestionRefresh.reconcile(entries, authoritativeTitles: [:])

        #expect(result.entries.isEmpty)
        #expect(result.removedIDs == [4, 9])
    }
}
