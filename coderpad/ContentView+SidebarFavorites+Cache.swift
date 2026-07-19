//
//  ContentView+SidebarFavorites+Cache.swift
//  coderpad
//
//  The memo behind the sidebar's Favorites section, so its rows are derived only
//  when the favourites, their order, or the caches their titles come from change.
//

import Foundation
import SwiftUI

/// Memo of the sidebar's favourite rows.
///
/// `favoritesSection` derived them from scratch on every `body` pass — the order
/// reconciliation, the per-account title dictionaries over the whole pads and
/// questions caches, and the per-row resolution — and the sidebar observes several
/// stores, so an unrelated change (a selection, a quota refresh, an account health
/// poll) re-ran the lot (#2107).
///
/// A plain reference type (not `@Observable`), like ``MenuBarListCache``, so `body`
/// can refresh it without mutating SwiftUI state mid-evaluation.
@MainActor
final class FavoriteEntriesCache {
    /// What the cached rows were built from; `nil` until the first build.
    var signature: Int?
    var entries: [Sidebar.FavoriteEntry] = []
}

extension Sidebar {
    /// The favourite rows to show, rebuilt only when their inputs change (#2107).
    /// Called from `favoritesSection`, before anything reads the rows.
    func refreshedFavoriteEntries() -> [FavoriteEntry] {
        let signature = favoritesSignature()
        guard favoriteEntriesCache.signature != signature else { return favoriteEntriesCache.entries }

        favoriteEntriesCache.signature = signature
        favoriteEntriesCache.entries = computeFavoriteEntries()
        return favoriteEntriesCache.entries
    }

    /// A signature of everything the rows are derived from: which accounts are in
    /// view, their favourites (ids *and* stored titles, which the rows fall back to),
    /// and the saved drag order.
    private func favoritesSignature() -> Int {
        var hasher = Hasher()
        hasher.combine(isMergedView)
        if isMergedView {
            hasher.combine(favoritesOrder.mergedOrder)
            for account in accounts.mergeableAccounts {
                combine(account: account.id, into: &hasher)
            }
        } else if let accountID {
            combine(account: accountID, into: &hasher)
        }
        return hasher.finalize()
    }

    /// One account's contribution to the signature. Titles are resolved against the
    /// pads and questions caches, whose write generation stands in for their contents
    /// so the check stays O(favourites) rather than hashing every cached pad and
    /// question — the same trade the merged list views make (#1234). The counts cover
    /// the one population that doesn't bump a generation: `get`'s disk fallback.
    private func combine(account: UUID, into hasher: inout Hasher) {
        hasher.combine(account)
        hasher.combine(favoritePads.titledFavorites(account: account))
        hasher.combine(favorites.titledFavorites(account: account))
        hasher.combine(favoritesOrder.byAccount[account] ?? [])
        hasher.combine(padsCache.writeGeneration[account] ?? 0)
        hasher.combine(questionsCache.writeGeneration[account] ?? 0)
        hasher.combine(padsCache.cached(account).count)
        hasher.combine(questionsCache.cached(account).count)
    }
}
