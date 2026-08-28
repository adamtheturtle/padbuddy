//
//  PadBuddyTests+CloudTombstoneClamp.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Cloud tombstone clamping")
struct CloudTombstoneClampTests {
    private func tombstones(_ count: Int, from start: Date = Date(timeIntervalSince1970: 0))
        -> [String: Date] {
        Dictionary(uniqueKeysWithValues: (0 ..< count).map {
            ("id-\($0)", start.addingTimeInterval(Double($0)))
        })
    }

    @Test func `a blob within the limit is returned untouched`() {
        let input = tombstones(4)

        #expect(CloudTombstoneClamp.clamped(input, limit: 10) == input)
    }

    @Test func `the newest removals are the ones kept`() {
        let clamped = CloudTombstoneClamp.clamped(tombstones(10), limit: 3)

        #expect(clamped.count == 3)
        #expect(Set(clamped.keys) == ["id-9", "id-8", "id-7"])
    }

    /// Two devices clamping the same blob have to land on the same subset, or each
    /// re-uploads a different one and the removals never settle.
    @Test func `ties break deterministically on the id`() {
        let same = Date(timeIntervalSince1970: 500)
        let input = ["b": same, "a": same, "c": same]

        let first = CloudTombstoneClamp.clamped(input, limit: 2)
        let second = CloudTombstoneClamp.clamped(input, limit: 2)

        #expect(first == second)
        #expect(Set(first.keys) == ["a", "b"])
    }

    @Test func `each account is clamped independently`() {
        let blob = ["one": tombstones(6), "two": tombstones(2)]

        let clamped = CloudTombstoneClamp.clamped(blob, limit: 4)

        #expect(clamped["one"]?.count == 4)
        #expect(clamped["two"]?.count == 2)
    }

    /// The bound the favourites mirrors actually apply, so a change to either cap is
    /// visible here rather than only at the next oversized sync.
    @Test func `the favourites stores clamp at their membership cap`() {
        let over = tombstones(FavoritePadsStore.maxEntriesPerAccount + 7)

        let clamped = CloudTombstoneClamp.clamped(over, limit: FavoritePadsStore.maxEntriesPerAccount)

        #expect(clamped.count == FavoritePadsStore.maxEntriesPerAccount)
        #expect(FavoritePadsStore.maxEntriesPerAccount == FavoriteQuestionsStore.maxEntriesPerAccount)
    }
}
