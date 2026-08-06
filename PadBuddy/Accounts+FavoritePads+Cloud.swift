//
//  Accounts+FavoritePads+Cloud.swift
//  coderpad
//
//  The iCloud mirroring and reconciliation half of FavoritePadsStore, split from
//  Accounts+FavoritePads.swift to keep that file within the length lint, as
//  FavoritesOrder+Cloud.swift does for the order store. The local
//  read/pin/persist half stays there.
//

import Foundation

extension FavoritePadsStore {
    /// Pushes the current favourites (and their deletion tombstones, #738) up to
    /// iCloud, keyed by each account's stable sync id. No-op when iCloud is
    /// unavailable (#536).
    func mirrorToCloud() {
        guard CloudSyncStore.shared.isAvailable else { return }

        // Indexed once rather than scanned per account (#2439).
        let syncIDs = AccountsStore.shared.syncIDsByAccountID
        let syncID: (UUID) -> String? = { syncIDs[$0] }
        if let data = try? SharedCoders.encoder.encode(CloudSyncMerge.toCloud(byAccount, syncID: syncID)) {
            CloudSyncStore.shared.mirror(data, forKey: Self.cloudKey)
        }
        // Skipped when neither the tombstones nor the identities keying them have
        // moved since the last successful upload — the blob would be byte-identical
        // (#2080). Both have to match: an account re-keyed without any tombstone
        // change still needs the mirror rewritten under its new identity.
        guard mirroredTombstones?.tombstones != removedAt || mirroredTombstones?.syncIDs != syncIDs else { return }

        if let data = try? SharedCoders.encoder.encode(CloudSyncMerge.toCloud(removedAt, syncID: syncID)) {
            CloudSyncStore.shared.mirror(data, forKey: Self.cloudTombstonesKey)
            mirroredTombstones = (removedAt, syncIDs)
        }
    }

    /// Pulls the iCloud favourites and merges them into the local set (additive union
    /// per account), then resolves deletion tombstones so an unfavorite made on
    /// another Mac converges here instead of being unioned back (#738), and persists.
    /// Called once accounts have loaded and on every external iCloud change. No-op
    /// when iCloud is unavailable (#536).
    func syncFromCloud() {
        guard let data = CloudSyncStore.shared.data(forKey: Self.cloudKey),
              let decoded = try? SharedCoders.decoder.decode([String: [FavoritePad]].self, from: data) else { return }

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
                                                   id: \.id, addedAt: \.addedAt)
            merged[account] = resolved.items
            tombstones[account] = resolved.tombstones
        }
        guard merged != byAccount || tombstones != removedAt else { return }

        byAccount = merged
        removedAt = tombstones
        save(account: nil)
    }
}
