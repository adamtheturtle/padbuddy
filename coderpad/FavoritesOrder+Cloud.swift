//
//  FavoritesOrder+Cloud.swift
//  coderpad
//
//  The iCloud mirroring and reconciliation half of FavoritesOrderStore, split
//  from FavoritesOrder.swift to keep that file within the length lint. The
//  local read/reorder/persist half stays there.
//

import Foundation

extension FavoritesOrderStore {
    /// A merged-order entry as mirrored to iCloud: the account travels as its
    /// stable sync id, not the per-device UUID (#1151).
    private struct CloudMergedRef: Codable {
        let account: String
        let ref: FavoriteRef
    }

    /// Deletes a removed account's entries from the mirrored cloud blobs (#1150).
    func removeFromCloud(syncID: String) {
        guard CloudSyncStore.shared.isAvailable else { return }

        if let data = CloudSyncStore.shared.data(forKey: Self.cloudKey),
           var cloud = try? JSONDecoder().decode([String: [FavoriteRef]].self, from: data),
           cloud.removeValue(forKey: syncID) != nil,
           let updated = try? JSONEncoder().encode(cloud) {
            CloudSyncStore.shared.mirror(updated, forKey: Self.cloudKey)
        }
        if let data = CloudSyncStore.shared.data(forKey: Self.cloudStampsKey),
           var stamps = try? JSONDecoder().decode([String: Date].self, from: data),
           stamps.removeValue(forKey: syncID) != nil,
           let updated = try? JSONEncoder().encode(stamps) {
            CloudSyncStore.shared.mirror(updated, forKey: Self.cloudStampsKey)
        }
    }

    /// Pushes the current order (and its per-account rearrange stamps, #739) up to
    /// iCloud, keyed by each account's stable sync id. No-op when iCloud is
    /// unavailable (#536).
    func mirrorToCloud() {
        guard CloudSyncStore.shared.isAvailable else { return }

        let syncID: (UUID) -> String? = { uuid in
            AccountsStore.shared.accounts.first { $0.id == uuid }?.syncID
        }
        if let data = try? JSONEncoder().encode(CloudSyncMerge.toCloud(byAccount, syncID: syncID)) {
            CloudSyncStore.shared.mirror(data, forKey: Self.cloudKey)
        }
        if let data = try? JSONEncoder().encode(CloudSyncMerge.toCloud(orderChangedAt, syncID: syncID)) {
            CloudSyncStore.shared.mirror(data, forKey: Self.cloudStampsKey)
        }
    }

    /// Mirrors the merged (cross-account) order to iCloud with accounts mapped to
    /// their stable sync ids: the class contract says the interleaved order syncs,
    /// but it used to be device-local (#1151). Entries whose account has no sync
    /// identity are skipped rather than leaking a per-device UUID.
    func mirrorMergedToCloud() {
        guard CloudSyncStore.shared.isAvailable else { return }

        let syncID: (UUID) -> String? = { uuid in
            AccountsStore.shared.accounts.first { $0.id == uuid }?.syncID
        }
        let cloudRefs: [CloudMergedRef] = mergedOrder.compactMap { entry in
            syncID(entry.account).map { CloudMergedRef(account: $0, ref: entry.ref) }
        }
        if let data = try? JSONEncoder().encode(cloudRefs) {
            CloudSyncStore.shared.mirror(data, forKey: Self.cloudMergedKey)
        }
        if let mergedChangedAt, let data = try? JSONEncoder().encode(mergedChangedAt) {
            CloudSyncStore.shared.mirror(data, forKey: Self.cloudMergedStampKey)
        }
    }

    /// Pulls the iCloud order and reconciles it per account, last-reorder-wins: a
    /// cloud order stamped newer than the local one is adopted wholesale (any refs
    /// it doesn't mention are re-appended by the on-read reconciliation), so a drag
    /// on one Mac finally lands on the others (#739). Without a newer cloud stamp
    /// the previous behavior holds: union keeping local positions and appending
    /// cloud-only refs. Reconciliation on read still drops any ref that isn't an
    /// actual favourite, so a stale ref can't surface. Called once accounts have
    /// loaded and on every external iCloud change. No-op when iCloud is
    /// unavailable (#536).
    func syncFromCloud() {
        guard let data = CloudSyncStore.shared.data(forKey: Self.cloudKey),
              let cloud = try? JSONDecoder().decode([String: [FavoriteRef]].self, from: data) else { return }

        let uuidForSyncID: (String) -> UUID? = { identity in
            AccountsStore.shared.accounts.first { $0.syncID == identity }?.id
        }
        var cloudStamps: [UUID: Date] = [:]
        if let data = CloudSyncStore.shared.data(forKey: Self.cloudStampsKey),
           let decoded = try? JSONDecoder().decode([String: Date].self, from: data) {
            for (identity, stamp) in decoded {
                guard let uuid = uuidForSyncID(identity) else { continue }

                cloudStamps[uuid] = stamp
            }
        }
        var merged = CloudSyncMerge.mergeArrays(cloud: cloud, into: byAccount,
                                                uuidForSyncID: uuidForSyncID)
        var stamps = orderChangedAt
        for (identity, rawCloudList) in cloud {
            guard let uuid = uuidForSyncID(identity), let cloudStamp = cloudStamps[uuid] else { continue }

            let cloudList = Array(rawCloudList.prefix(Self.maxOrderEntriesPerAccount))
            let localStamp = orderChangedAt[uuid] ?? .distantPast
            // Strictly-newer wins as before; *equal* stamps with different orders
            // (two devices dragged in the same instant) would otherwise leave the
            // devices permanently divergent, so a deterministic tie-break makes
            // both sides adopt the same order (#1784).
            let wins = cloudStamp > localStamp
                || (cloudStamp == localStamp && cloudList != (byAccount[uuid] ?? [])
                    && Self.cloudWinsStampTie(cloud: Self.token(for: cloudList),
                                              local: Self.token(for: byAccount[uuid] ?? [])))
            guard wins else { continue }

            merged[uuid] = cloudList
            stamps[uuid] = cloudStamp
        }
        if merged != byAccount || stamps != orderChangedAt {
            byAccount = merged
            orderChangedAt = stamps
            save()
        }
        syncMergedFromCloud(uuidForSyncID: uuidForSyncID)
    }

    /// Adopts the cloud merged (cross-account) order when it is stamped newer than
    /// the local one, mapping stable sync ids back to this device's account UUIDs;
    /// unmapped accounts drop and the on-read reconciliation re-appends anything
    /// missing (#1151).
    private func syncMergedFromCloud(uuidForSyncID: (String) -> UUID?) {
        guard let stampData = CloudSyncStore.shared.data(forKey: Self.cloudMergedStampKey),
              let cloudStamp = try? JSONDecoder().decode(Date.self, from: stampData),
              let data = CloudSyncStore.shared.data(forKey: Self.cloudMergedKey),
              let cloudRefs = try? JSONDecoder().decode([CloudMergedRef].self, from: data)
        else { return }

        let adopted: [MergedFavoriteRef] = cloudRefs.prefix(Self.maxMergedOrderEntries).compactMap { entry in
            uuidForSyncID(entry.account).map { MergedFavoriteRef(account: $0, ref: entry.ref) }
        }
        // Strictly-newer wins; equal stamps with different orders fall to the
        // deterministic tie-break so both devices converge (#1784).
        let localStamp = mergedChangedAt ?? .distantPast
        let wins = cloudStamp > localStamp
            || (cloudStamp == localStamp && adopted != mergedOrder
                && Self.cloudWinsStampTie(cloud: Self.token(for: adopted),
                                          local: Self.token(for: mergedOrder)))
        guard wins else { return }
        guard adopted != mergedOrder else {
            mergedChangedAt = cloudStamp
            UserDefaults.standard.set(cloudStamp, forKey: Self.mergedStampKey)
            return
        }

        mergedOrder = adopted
        mergedChangedAt = cloudStamp
        saveMerged()
    }

    /// The deterministic winner for orders whose rearrange stamps are exactly
    /// equal: both devices see the same two candidate orders, so comparing their
    /// stable tokens picks the same winner on both sides and the lists converge
    /// instead of each device keeping its own forever (#1784).
    private static func cloudWinsStampTie(cloud: String, local: String) -> Bool {
        cloud < local
    }

    private static func token(for ref: FavoriteRef) -> String {
        switch ref {
        case let .pad(id): "p:\(id)"
        case let .question(id): "q:\(id)"
        }
    }

    private static func token(for refs: [FavoriteRef]) -> String {
        refs.map(token(for:)).joined(separator: "|")
    }

    private static func token(for refs: [MergedFavoriteRef]) -> String {
        refs.map { "\($0.account.uuidString)/\(token(for: $0.ref))" }.joined(separator: "|")
    }
}
