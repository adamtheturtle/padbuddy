//
//  MergedAccountOptionsCache.swift
//  coderpad
//
//  Per-render memo for the merged filter bars' account-derived option lists.
//

import Foundation

/// Caches the Account chip's option ids and its `[UUID: String]` name index.
///
/// `filterBar` re-renders on every keystroke, filter toggle, and selection settle,
/// and each pass rebuilt the whole name dictionary and the mergeable-id array from
/// `accounts` — which change only when an account is added, removed, or renamed
/// (#2467, #2468). A class, like the other per-render caches here, so `body` can
/// refresh it without mutating SwiftUI state mid-evaluation.
@MainActor
final class MergedAccountOptionsCache {
    private(set) var ids: [UUID] = []
    private(set) var names: [UUID: String] = [:]
    /// What the cached values were built from: the mergeable ids in order, paired
    /// with the names, so a rename invalidates as surely as an add or a removal.
    private var signature: [String] = []

    /// Refreshes from `accounts` when anything the options depend on has changed.
    func refresh(_ accounts: [Account], mergeable: [Account]) {
        // Keep the first occurrence of each UUID so filter chips never see duplicate
        // option identities while names already uniqued (#4577).
        var seen = Set<UUID>()
        let uniqueMergeable = mergeable.filter { seen.insert($0.id).inserted }
        let signature = uniqueMergeable.map { "\($0.id.uuidString)\u{1}\($0.name)" }
        guard signature != self.signature else { return }

        self.signature = signature
        ids = uniqueMergeable.map(\.id)
        names = Dictionary(accounts.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    /// The chip's formatter, resolving each option in O(1).
    func formatter() -> (UUID) -> String {
        let names = names
        return { names[$0] ?? String(localized: "Account") }
    }
}
