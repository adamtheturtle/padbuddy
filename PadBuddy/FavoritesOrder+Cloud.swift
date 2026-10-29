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
           var cloud = try? SharedCoders.decoder.decode([String: [FavoriteRef]].self, from: data),
           cloud.removeValue(forKey: syncID) != nil,
           let updated = try? SharedCoders.encoder.encode(cloud) {
            CloudSyncStore.shared.mirror(updated, forKey: Self.cloudKey)
        }
        if let data = CloudSyncStore.shared.data(forKey: Self.cloudStampsKey),
           var stamps = try? SharedCoders.decoder.decode([String: Date].self, from: data),
           stamps.removeValue(forKey: syncID) != nil,
           let updated = try? SharedCoders.encoder.encode(stamps) {
            CloudSyncStore.shared.mirror(updated, forKey: Self.cloudStampsKey)
        }
        // The merged (cross-account) blob is keyed by the same identity and was left
        // untouched, so a removed account's pads and questions stayed in the
        // cross-account order in iCloud indefinitely and were re-adopted the moment
        // that identity was configured again (#4809).
        guard let data = CloudSyncStore.shared.data(forKey: Self.cloudMergedKey),
              let cloud = try? SharedCoders.decoder.decode([CloudMergedRef].self, from: data)
        else { return }

        let remaining = cloud.filter { $0.account != syncID }
        guard remaining.count != cloud.count,
              let updated = try? SharedCoders.encoder.encode(remaining) else { return }

        CloudSyncStore.shared.mirror(updated, forKey: Self.cloudMergedKey)
        // Stamped with the removal: the merged order is reconciled last-reorder-wins,
        // so a shortened blob published under the old stamp is ignored everywhere.
        if let stamp = try? SharedCoders.encoder.encode(Date()) {
            CloudSyncStore.shared.mirror(stamp, forKey: Self.cloudMergedStampKey)
        }
    }

    /// Pushes the current order (and its per-account rearrange stamps, #739) up to
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
        if let data = try? SharedCoders.encoder.encode(CloudSyncMerge.toCloud(orderChangedAt, syncID: syncID)) {
            CloudSyncStore.shared.mirror(data, forKey: Self.cloudStampsKey)
        }
    }

    /// Mirrors the merged (cross-account) order to iCloud with accounts mapped to
    /// their stable sync ids: the class contract says the interleaved order syncs,
    /// but it used to be device-local (#1151). Entries whose account has no sync
    /// identity are skipped rather than leaking a per-device UUID.
    func mirrorMergedToCloud() {
        guard CloudSyncStore.shared.isAvailable else { return }

        // Indexed once rather than scanned per account (#2439).
        let syncIDs = AccountsStore.shared.syncIDsByAccountID
        let syncID: (UUID) -> String? = { syncIDs[$0] }
        let cloudRefs: [CloudMergedRef] = mergedOrder.compactMap { entry in
            syncID(entry.account).map { CloudMergedRef(account: $0, ref: entry.ref) }
        }
        if let data = try? SharedCoders.encoder.encode(cloudRefs) {
            CloudSyncStore.shared.mirror(data, forKey: Self.cloudMergedKey)
        }
        // Unconditional. `mergedChangedAt` is nil until the merged order has been
        // rearranged on this device — `restoreMerged` does not set it either — so a
        // legitimate merged order could be published with no stamp, and the receiving
        // side required one, which silently discarded that order on every other
        // device (#4811).
        if let data = try? SharedCoders.encoder.encode(mergedChangedAt ?? .distantPast) {
            CloudSyncStore.shared.mirror(data, forKey: Self.cloudMergedStampKey)
        }
    }

    /// Pulls the iCloud order and reconciles it per account, last-reorder-wins: a
    /// cloud order stamped newer than the local one is adopted wholesale (any refs
    /// it doesn't mention are re-appended by the on-read reconciliation), so a drag
    /// on one Mac finally lands on the others (#739). Without a newer cloud stamp
    /// the previous behavior holds: union keeping local positions and appending
    /// actual favourite, so a stale ref can't surface. Called once accounts have
    /// actual favourite, so a stale ref cannot surface. Called once accounts have
    /// loaded and on every external iCloud change. No-op when iCloud is
    /// unavailable (#536).
    func syncFromCloud() {
        let accountIDs = AccountsStore.shared.syncIdentityIndex.accountIDsBySyncID
        let uuidForSyncID: (String) -> UUID? = { accountIDs[$0] }
        // The merged reconciliation does not depend on the per-account one, and used
        // to sit on the last line of this function — behind the guard below. A
        // notification for either merged key therefore did nothing at all whenever the
        // per-account blob was absent or undecodable: a device that has only ever
        // dragged in the combined view, or a fresh one receiving the merged blob
        // first (#4810).
        defer { syncMergedFromCloud(uuidForSyncID: uuidForSyncID) }

        guard let data = CloudSyncStore.shared.data(forKey: Self.cloudKey),
              let cloud = try? SharedCoders.decoder.decode([String: [FavoriteRef]].self, from: data) else { return }

        var cloudStamps: [UUID: Date] = [:]
        if let data = CloudSyncStore.shared.data(forKey: Self.cloudStampsKey),
           let decoded = try? SharedCoders.decoder.decode([String: Date].self, from: data) {
            for (identity, stamp) in decoded {
                guard let uuid = uuidForSyncID(identity) else { continue }

                cloudStamps[uuid] = FutureTimestampPolicy.clamped(stamp)
            }
        }
        // Bound every decoded list before either reconciliation path sees it. Legacy
        // and interrupted mirrors may have no stamp, so clamping only in the stamped
        // last-writer-wins branch let their raw arrays bypass the declared cap (#5147).
        let boundedCloud = cloud.mapValues(Self.boundedCloudOrder)
        var merged = CloudSyncMerge.mergeArrays(cloud: boundedCloud, into: byAccount,
                                                uuidForSyncID: uuidForSyncID)
        var stamps = orderChangedAt.mapValues { FutureTimestampPolicy.clamped($0) }
        for (identity, cloudList) in boundedCloud {
            guard let uuid = uuidForSyncID(identity), let cloudStamp = cloudStamps[uuid] else { continue }

            let localStamp = stamps[uuid] ?? .distantPast
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
    }

    static func boundedCloudOrder(_ order: [FavoriteRef]) -> [FavoriteRef] {
        Array(order.prefix(maxOrderEntriesPerAccount))
    }

    /// Adopts the cloud merged (cross-account) order when it is stamped newer than
    /// the local one, mapping stable sync ids back to this device's account UUIDs;
    /// unmapped accounts drop and the on-read reconciliation re-appends anything
    /// missing (#1151).
    private func syncMergedFromCloud(uuidForSyncID: (String) -> UUID?) {
        guard let data = CloudSyncStore.shared.data(forKey: Self.cloudMergedKey),
              let cloudRefs = try? SharedCoders.decoder.decode([CloudMergedRef].self, from: data)
        else { return }

        // A missing stamp reads as `.distantPast` rather than aborting, as the
        // per-account path already does with `orderChangedAt[uuid] ?? .distantPast`.
        // Requiring one discarded orders that were legitimately published without it
        // (#4811).
        var cloudStamp = Date.distantPast
        if let stampData = CloudSyncStore.shared.data(forKey: Self.cloudMergedStampKey),
           let decoded = try? SharedCoders.decoder.decode(Date.self, from: stampData) {
            cloudStamp = FutureTimestampPolicy.clamped(decoded)
        }
        let adopted: [MergedFavoriteRef] = cloudRefs.prefix(Self.maxMergedOrderEntries).compactMap { entry in
            uuidForSyncID(entry.account).map { MergedFavoriteRef(account: $0, ref: entry.ref) }
        }
        // Strictly-newer wins; equal stamps with different orders fall to the
        // deterministic tie-break so both devices converge (#1784).
        let syncIDs = AccountsStore.shared.syncIDsByAccountID
        let syncID: (UUID) -> String? = { syncIDs[$0] }
        let localStamp = mergedChangedAt.map { FutureTimestampPolicy.clamped($0) } ?? .distantPast
        let wins = cloudStamp > localStamp
            || (cloudStamp == localStamp && adopted != mergedOrder
                && Self.cloudWinsStampTie(cloud: Self.token(for: adopted, syncID: syncID),
                                          local: Self.token(for: mergedOrder, syncID: syncID)))
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

    /// The merged-order token, spelled with each account's stable sync identity.
    ///
    /// It used to embed `Account.id`, which is a per-device random UUID — the very
    /// reason the cloud blob keys on the sync id. Each device compared a pair of
    /// strings spelled with its own UUIDs, so `cloud < local` could answer
    /// differently on each side and both kept their own order: the exact
    /// non-convergence the tie-break exists to close (#4812). An account with no
    /// sync identity cannot appear in the cloud order at all, so it contributes only
    /// its ref.
    static func token(for refs: [MergedFavoriteRef], syncID: (UUID) -> String?) -> String {
        refs.map { entry in
            "\(syncID(entry.account) ?? "-")/\(token(for: entry.ref))"
        }.joined(separator: "|")
    }
}
