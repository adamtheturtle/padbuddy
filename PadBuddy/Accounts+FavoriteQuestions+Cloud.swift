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
        guard let data = CloudSyncStore.shared.data(forKey: Self.cloudKey) else { return }
        guard let decoded = try? SharedCoders.decoder
            .decode([String: [FavoriteQuestion]].self, from: data) else { return }

        // The mirror is cross-device input: clamp it like the local blob (#1788).
        let cloud = decoded.mapValues(Self.sanitized)

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
            tombstones = CloudSyncMerge.mergeTimestamps(cloud: cloudTombstones, into: tombstones,
                                                        uuidForSyncID: uuidForSyncID)
        }
        for (account, entries) in merged {
            let resolved = CloudTombstones.resolve(items: entries,
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
