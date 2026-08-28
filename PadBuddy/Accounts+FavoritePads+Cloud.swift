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
import os

extension FavoritePadsStore {
    private static var cloudLogger: Logger {
        Logger(subsystem: "com.coderpad.app", category: "favorite-pads-cloud")
    }

    static func encodeCloud<Value: Encodable>(
        _ value: Value,
        using encode: (Value) throws -> Data = { try SharedCoders.encoder.encode($0) }
    ) -> Data? {
        do {
            return try encode(value)
        } catch {
            cloudLogger.error("Could not encode favorite pads for iCloud; the previous mirror remains: \(error)")
            return nil
        }
    }

    /// Pushes the current favourites (and their deletion tombstones, #738) up to
    /// iCloud, keyed by each account's stable sync id. No-op when iCloud is
    /// unavailable (#536).
    func mirrorToCloud() {
        guard CloudSyncStore.shared.isAvailable else { return }

        // Indexed once rather than scanned per account (#2439).
        let syncIDs = AccountsStore.shared.syncIDsByAccountID
        let syncID: (UUID) -> String? = { syncIDs[$0] }
        // Tombstones first, for the same reason as the local write in `save`: a
        // membership blob published without the tombstones explaining its removals is
        // exactly the state in which another device's additive merge unions the
        // unfavourited pad back and re-uploads it (#4814).
        //
        // Skipped when neither the tombstones nor the identities keying them have
        // moved since the last successful upload — the blob would be byte-identical
        // (#2080). Both have to match: an account re-keyed without any tombstone
        // change still needs the mirror rewritten under its new identity.
        if mirroredTombstones?.tombstones != removedAt || mirroredTombstones?.syncIDs != syncIDs,
           let data = Self.encodeCloud(CloudSyncMerge.toCloud(removedAt, syncID: syncID)) {
            CloudSyncStore.shared.mirror(data, forKey: Self.cloudTombstonesKey)
            // Recorded only once the store reads the blob back. `mirror` is
            // fire-and-forget against a KVS that silently drops a write past its
            // per-key or total quota; marking it mirrored on a successful *encode*
            // suppressed every later retry for as long as the tombstones were
            // unchanged, so those removals never converged (#4816).
            let accepted = CloudSyncStore.shared.data(forKey: Self.cloudTombstonesKey) == data
            mirroredTombstones = accepted ? (removedAt, syncIDs) : nil
        }
        if let data = Self.encodeCloud(CloudSyncMerge.toCloud(byAccount, syncID: syncID)) {
            CloudSyncStore.shared.mirror(data, forKey: Self.cloudKey)
        }
    }

    /// Pulls the iCloud favourites and merges them into the local set (additive union
    /// per account), then resolves deletion tombstones so an unfavorite made on
    /// another Mac converges here instead of being unioned back (#738), and persists.
    /// Called once accounts have loaded and on every external iCloud change. No-op
    /// when iCloud is unavailable (#536).
    func syncFromCloud() {
        // The tombstone blob changes independently of the membership blob — a remote
        // unfavourite writes only the former — which is why the observer watches both
        // keys (#2525). Returning early when the membership blob was absent or
        // undecodable dropped a tombstone-only change anyway, on a fresh device or one
        // whose favourites had never been mirrored (#4813).
        //
        // The mirror is cross-device input: clamp it like the local blob (#1788).
        let cloud: [String: [FavoritePad]]
        if let data = CloudSyncStore.shared.data(forKey: Self.cloudKey),
           let decoded = try? SharedCoders.decoder.decode([String: [FavoritePad]].self, from: data) {
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
