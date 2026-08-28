//
//  PadBuddyTests+FavoritesOrder.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

// MARK: - Favorites order reconciliation

/// The shared reconciliation behind `order(present:account:)` and `merged(present:)`,
/// which are now memoized against their inputs (#2113) — so the reconciliation itself
/// is exercised here, independent of the memo.
@Suite("Favorites order reconciliation")
struct FavoritesOrderReconcileTests {
    @Test func `corrupt persisted order is discarded instead of retried every launch`() throws {
        let suite = "FavoritesOrderTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("not-json".utf8), forKey: "order")

        let decoded: [FavoriteRef]? = FavoritesOrderStore.decodePersisted(
            [FavoriteRef].self,
            key: "order",
            defaults: defaults
        )

        #expect(decoded == nil)
        #expect(defaults.object(forKey: "order") == nil)
    }

    @Test func `keeps the stored order and appends the rest of present`() {
        let result = FavoritesOrderStore.reconcile(
            stored: [FavoriteRef.question(7), .pad("b")],
            present: [FavoriteRef.pad("a"), .pad("b"), .question(7)]
        )
        #expect(result == [.question(7), .pad("b"), .pad("a")])
    }

    @Test func `drops stored refs that are no longer favourites`() {
        let result = FavoritesOrderStore.reconcile(
            stored: [FavoriteRef.pad("gone"), .pad("a")],
            present: [FavoriteRef.pad("a")]
        )
        #expect(result == [.pad("a")])
    }

    @Test func `deduplicates a corrupt stored order`() {
        let result = FavoritesOrderStore.reconcile(
            stored: [FavoriteRef.pad("a"), .pad("a"), .question(1)],
            present: [FavoriteRef.pad("a"), .question(1)]
        )
        #expect(result == [.pad("a"), .question(1)])
    }

    @Test func `yields present unchanged with no stored order`() {
        let present = [FavoriteRef.pad("a"), .question(2)]
        #expect(FavoritesOrderStore.reconcile(stored: [], present: present) == present)
    }

    @Test func `reconciles merged refs across accounts`() {
        let first = UUID()
        let second = UUID()
        let firstRef = MergedFavoriteRef(account: first, ref: .pad("a"))
        let secondRef = MergedFavoriteRef(account: second, ref: .pad("a"))
        let result = FavoritesOrderStore.reconcile(stored: [secondRef], present: [firstRef, secondRef])
        #expect(result == [secondRef, firstRef])
    }
}

@Suite("Merged favorites order stamping (#4716, #4717)", .serialized)
@MainActor
struct MergedFavoritesOrderStampTests {
    private var store: FavoritesOrderStore {
        .shared
    }

    private func reset() {
        store.mergedOrder = []
        store.mergedChangedAt = nil
    }

    @Test func `removing an account stamps the merged order`() {
        defer { reset() }
        let removed = UUID()
        let kept = UUID()
        store.mergedOrder = [
            MergedFavoriteRef(account: removed, ref: .pad("a")),
            MergedFavoriteRef(account: kept, ref: .pad("b"))
        ]
        store.mergedChangedAt = Date(timeIntervalSinceReferenceDate: 0)

        store.remove(account: removed)

        // Without the bump, the mirrored pre-removal order compares as newer and merges
        // the removed account's refs back in.
        #expect(store.mergedOrder.allSatisfy { $0.account != removed })
        let stamp = store.mergedChangedAt
        #expect(stamp != nil)
        #expect(stamp.map { $0 > Date(timeIntervalSinceReferenceDate: 0) } == true)
    }

    @Test func `removing an account with nothing to drop leaves the stamp alone`() {
        defer { reset() }
        let baseline = Date(timeIntervalSinceReferenceDate: 0)
        store.mergedOrder = []
        store.mergedChangedAt = baseline

        store.remove(account: UUID())

        #expect(store.mergedChangedAt == baseline)
    }
}
