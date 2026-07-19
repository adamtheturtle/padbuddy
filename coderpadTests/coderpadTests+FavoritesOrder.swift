//
//  coderpadTests+FavoritesOrder.swift
//  coderpadTests
//

@testable import CoderPad
import Foundation
import Testing

// MARK: - Favorites order reconciliation

/// The shared reconciliation behind `order(present:account:)` and `merged(present:)`,
/// which are now memoized against their inputs (#2113) — so the reconciliation itself
/// is exercised here, independent of the memo.
@Suite("Favorites order reconciliation")
struct FavoritesOrderReconcileTests {
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
