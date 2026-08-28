//
//  Accounts+FavoriteQuestions+Cloud.swift
//  coderpad
//
//  Merging starred questions with the iCloud mirror.
//

import Foundation
import os
import SwiftUI

@MainActor
extension FavoriteQuestionsStore {
    /// Pulls the iCloud favourites and merges them into the local set, unioning by
    /// question id so a title backfilled on only one device never forks an entry,
    /// then resolves deletion tombstones so an unstar made on another Mac converges
    /// here instead of being unioned back (#738), and persists. Called once accounts
    /// have loaded and on every external iCloud change. No-op when iCloud is
    /// unavailable (#536).
    func syncFromCloud() {
        // The tombstone blob changes independently of the membership blob — a remote
        // unstar writes only the former — which is why the observer watches both keys
        // (#2526). Returning early when the membership blob was absent or undecodable
        // dropped a tombstone-only change anyway, on a fresh device or one whose
        // favourites had never been mirrored (#4813).
        //
        // The mirror is cross-device input: clamp it like the local blob (#1788).
        let cloud: [String: [FavoriteQuestion]]
        if let data = CloudSyncStore.shared.data(forKey: Self.cloudKey),
           let decoded = try? SharedCoders.decoder.decode([String: [FavoriteQuestion]].self, from: data) {
            cloud = decoded.mapValues(Self.sanitized)
        } else if CloudSyncStore.shared.data(forKey: Self.cloudTombstonesKey) != nil {
            cloud = [:]
        } else {
            return
        }

        let accountIDs = AccountsStore.shared.syncIdentityIndex.accountIDsBySyncID
        let uuidForSyncID: (String) -> UUID? = { accountIDs[$0] }
        var merged = CloudSyncMerge.mergeArrays(cloud: cloud, into: byAccount,
                                                uuidForSyncID: uuidForSyncID) { $0.id }
        // The union keeps the local element for ids on both sides, so also adopt
        // titles renamed on another Mac (#762).
        merged = FavoriteTitleSync.adoptCloudTitles(
            merged: merged, cloud: cloud, uuidForSyncID: uuidForSyncID,
            id: { $0.id }, title: \.title
        )
        var tombstones = removedAt
        if let data = CloudSyncStore.shared.data(forKey: Self.cloudTombstonesKey),
           let cloudTombstones = try? SharedCoders.decoder.decode([String: [String: Date]].self, from: data) {
            // Clamped like the membership blob above: it comes from the same
            // untrusted mirror, and only the membership half was bounded (#4815).
            let clamped = CloudTombstoneClamp.clamped(cloudTombstones, limit: Self.maxEntriesPerAccount)
            tombstones = CloudSyncMerge.mergeTimestamps(cloud: clamped, into: tombstones,
                                                        uuidForSyncID: uuidForSyncID)
        }
        // Every account with either entries or tombstones, so a tombstone for an account
        // with no local favourites is still applied and retained (#4813).
        for account in Set(merged.keys).union(tombstones.keys) {
            let resolved = CloudTombstones.resolve(items: merged[account] ?? [],
                                                   tombstones: tombstones[account] ?? [:],
                                                   id: { String($0.id) }, addedAt: \.addedAt)
            merged[account] = resolved.items
            tombstones[account] = resolved.tombstones
        }
        guard merged != byAccount || tombstones != removedAt else { return }

        byAccount = merged
        removedAt = tombstones
        save()
        for account in merged.keys {
            WidgetSync.syncFavorites(account: account)
        }
    }
}
