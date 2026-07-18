//
//  FavoritesOrder.swift
//  coderpad
//
//  The single drag order that favourite pads and starred questions share in the
//  sidebar. Membership and titles still live in FavoritePadsStore and
//  FavoriteQuestionsStore; this records only the order the two kinds interleave in.
//

import Foundation
import os
import SwiftUI

/// The interleaved drag order of a sidebar's favourites — pads and starred questions in
/// one list — per account. Before this, the sidebar always listed every favourite pad
/// above every favourite question; now a single order spans both kinds so a question can
/// be dragged between two pads and stay there.
///
/// Membership stays in the two kind-specific stores (``FavoritePadsStore`` /
/// ``FavoriteQuestionsStore``); this records only the combined order, reconciled against
/// current membership on every read (see ``order(present:account:)``) so a newly
/// favourited item appends and an un-favourited one drops without bookkeeping at each
/// add/remove site. With no saved order yet, the reconciliation simply yields the
/// `present` order it's handed — pads then questions — so a first run matches the old
/// layout exactly and no migration is needed.
///
/// Persisted to UserDefaults as one JSON blob keyed by account id and mirrored to iCloud
/// keyed by each account's stable sync id, like the favourites themselves (#536).
@Observable
final class FavoritesOrderStore {
    static let shared = FavoritesOrderStore()
    private var byAccount: [UUID: [FavoriteRef]] = [:]
    private var mergedOrder: [MergedFavoriteRef] = []
    /// When each account's order was last rearranged on any device, so two Macs'
    /// orders can be reconciled last-reorder-wins: the plain array union always
    /// kept the local positions, so a drag on one Mac never landed on the other
    /// (#739). Mirrored to iCloud alongside the orders.
    private var orderChangedAt: [UUID: Date] = [:]
    private static let key = "favoritesOrder.v1"
    private static let mergedKey = "favoritesMergedOrder.v1"
    private static let stampsKey = "favoritesOrder.changedAt.v1"
    /// When the merged (cross-account) order was last rearranged on any device,
    /// so devices reconcile it last-reorder-wins like the per-account orders (#1151).
    private var mergedChangedAt: Date?
    /// The iCloud mirror, keyed by each account's stable sync id rather than the
    /// per-device `UUID`, under its own key (#536).
    private static let cloudKey = "favoritesOrder.cloud.v1"
    private static let cloudStampsKey = "favoritesOrder.changedAt.cloud.v1"
    private static let mergedStampKey = "favoritesMergedOrder.changedAt.v1"
    private static let cloudMergedKey = "favoritesMergedOrder.cloud.v1"
    private static let cloudMergedStampKey = "favoritesMergedOrder.changedAt.cloud.v1"
    /// Held so the external-change observation task isn't cancelled; the store is a
    /// singleton that lives for the whole process, so it's never explicitly stopped.
    private var cloudObserverTask: Task<Void, Never>?

    /// A merged-order entry as mirrored to iCloud: the account travels as its
    /// stable sync id, not the per-device UUID (#1151).
    private struct CloudMergedRef: Codable {
        let account: String
        let ref: FavoriteRef
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([UUID: [FavoriteRef]].self, from: data) {
            byAccount = decoded
        }
        if let data = UserDefaults.standard.data(forKey: Self.mergedKey),
           let decoded = try? JSONDecoder().decode([MergedFavoriteRef].self, from: data) {
            mergedOrder = decoded
        }
        if let data = UserDefaults.standard.data(forKey: Self.stampsKey),
           let decoded = try? JSONDecoder().decode([UUID: Date].self, from: data) {
            orderChangedAt = decoded
        }
        mergedChangedAt = UserDefaults.standard.object(forKey: Self.mergedStampKey) as? Date
        // Re-pull and merge whenever iCloud reports an external change to any of
        // our mirrored keys. The revision stamps must count too: KVS delivers keys
        // independently, and when the order blob arrived first the later stamp
        // notification used to be ignored, so the remote drag never applied (#1149).
        let observedKeys: Set<String> = [
            Self.cloudKey, Self.cloudStampsKey, Self.cloudMergedKey, Self.cloudMergedStampKey
        ]
        cloudObserverTask = Task { @MainActor in
            for await note in NotificationCenter.default.notifications(named: CloudSyncStore.didChangeExternally) {
                guard let key = note.userInfo?["key"] as? String, observedKeys.contains(key) else { continue }

                Self.shared.syncFromCloud()
            }
        }
    }
}

extension FavoritesOrderStore {
    /// The favourites for `account` in their stored drag order, reconciled against the
    /// `present` membership: stored refs that are still favourites keep their saved
    /// position, then any present ref not yet in the stored order is appended in
    /// `present` order (a just-added favourite lands at the end). Pure — it doesn't
    /// persist — so the order stays derivable from `present` until a drag rewrites it.
    func order(present: [FavoriteRef], account: UUID?) -> [FavoriteRef] {
        guard let account else { return present }

        let presentSet = Set(present)
        var result = (byAccount[account] ?? []).filter { presentSet.contains($0) }
        let have = Set(result)
        result.append(contentsOf: present.filter { !have.contains($0) })
        return result
    }

    /// Moves `ref` to sit immediately before `target` in the combined order and persists
    /// the result, seeding from the reconciled `present` order so the saved blob captures
    /// any not-yet-recorded favourites too (drag-to-reorder in the sidebar, #299). A no-op
    /// if either ref is absent or they're the same.
    func move(_ ref: FavoriteRef, before target: FavoriteRef, present: [FavoriteRef], account: UUID,
              undoManager: UndoManager? = nil) {
        guard ref != target else { return }

        var ordered = order(present: present, account: account)
        guard let from = ordered.firstIndex(of: ref), ordered.contains(target) else { return }

        let before = byAccount[account] ?? []
        ordered.remove(at: from)
        let insertAt = ordered.firstIndex(of: target) ?? ordered.count
        ordered.insert(ref, at: insertAt)
        byAccount[account] = ordered
        orderChangedAt[account] = Date()
        save()
        registerUndo(to: before, account: account, undoManager: undoManager, actionName: "Move Favorite")
    }

    /// Moves `ref` to the end of the combined order. This backs drops into the empty
    /// space below the final favorite row, where there is no row to use as a `before`
    /// target.
    func moveToEnd(_ ref: FavoriteRef, present: [FavoriteRef], account: UUID, undoManager: UndoManager? = nil) {
        var ordered = order(present: present, account: account)
        guard let from = ordered.firstIndex(of: ref), let last = ordered.indices.last, from != last else { return }

        let before = byAccount[account] ?? []
        ordered.remove(at: from)
        ordered.append(ref)
        byAccount[account] = ordered
        orderChangedAt[account] = Date()
        save()
        registerUndo(to: before, account: account, undoManager: undoManager, actionName: "Move Favorite")
    }

    /// The combined-view favourites in their stored cross-account order. This is separate
    /// from the per-account order above because merged rows can be dragged across accounts.
    func merged(present: [MergedFavoriteRef]) -> [MergedFavoriteRef] {
        let presentSet = Set(present)
        var result = mergedOrder.filter { presentSet.contains($0) }
        let have = Set(result)
        result.append(contentsOf: present.filter { !have.contains($0) })
        return result
    }

    func moveMerged(_ ref: MergedFavoriteRef, before target: MergedFavoriteRef, present: [MergedFavoriteRef],
                    undoManager: UndoManager? = nil) {
        guard ref != target else { return }

        var ordered = merged(present: present)
        guard let from = ordered.firstIndex(of: ref), ordered.contains(target) else { return }

        let before = mergedOrder
        ordered.remove(at: from)
        let insertAt = ordered.firstIndex(of: target) ?? ordered.count
        ordered.insert(ref, at: insertAt)
        mergedOrder = ordered
        mergedChangedAt = Date()
        saveMerged()
        registerMergedUndo(to: before, undoManager: undoManager, actionName: "Move Favorite")
    }

    func moveMergedToEnd(_ ref: MergedFavoriteRef, present: [MergedFavoriteRef], undoManager: UndoManager? = nil) {
        var ordered = merged(present: present)
        guard let from = ordered.firstIndex(of: ref), let last = ordered.indices.last, from != last else { return }

        let before = mergedOrder
        ordered.remove(at: from)
        ordered.append(ref)
        mergedOrder = ordered
        mergedChangedAt = Date()
        saveMerged()
        registerMergedUndo(to: before, undoManager: undoManager, actionName: "Move Favorite")
    }

    /// Drops an account's saved order, called when the account is removed or re-keyed so
    /// its favourite refs don't linger in UserDefaults, alongside the kind-specific
    /// stores (#379). `syncID` is the removed account's stable sync identity: the
    /// cloud merge is additive, so without an explicit cloud delete other devices
    /// keep the old order and can restore it when the same identity returns (#1150).
    func remove(account: UUID, syncID: String? = nil) {
        if let syncID { removeFromCloud(syncID: syncID) }

        let hadAccountOrder = byAccount[account] != nil
        let filteredMergedOrder = mergedOrder.filter { $0.account != account }
        guard hadAccountOrder || filteredMergedOrder.count != mergedOrder.count else { return }

        byAccount[account] = nil
        orderChangedAt[account] = nil
        mergedOrder = filteredMergedOrder
        save()
        saveMerged()
    }

    /// Deletes a removed account's entries from the mirrored cloud blobs (#1150).
    private func removeFromCloud(syncID: String) {
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

    private func save() {
        do {
            let data = try JSONEncoder().encode(byAccount)
            UserDefaults.standard.set(data, forKey: Self.key)
            let stamps = try JSONEncoder().encode(orderChangedAt)
            UserDefaults.standard.set(stamps, forKey: Self.stampsKey)
        } catch {
            let reason = error.localizedDescription
            persistenceLogger.error("Failed to encode favorites order: \(reason, privacy: .public)")
        }
        mirrorToCloud()
    }

    private func saveMerged() {
        do {
            let data = try JSONEncoder().encode(mergedOrder)
            UserDefaults.standard.set(data, forKey: Self.mergedKey)
        } catch {
            let reason = error.localizedDescription
            persistenceLogger.error("Failed to encode merged favorites order: \(reason, privacy: .public)")
        }
        if let mergedChangedAt {
            UserDefaults.standard.set(mergedChangedAt, forKey: Self.mergedStampKey)
        }
        mirrorMergedToCloud()
    }

    /// Mirrors the merged (cross-account) order to iCloud with accounts mapped to
    /// their stable sync ids: the class contract says the interleaved order syncs,
    /// but it used to be device-local (#1151). Entries whose account has no sync
    /// identity are skipped rather than leaking a per-device UUID.
    private func mirrorMergedToCloud() {
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

    private func restore(_ entries: [FavoriteRef], account: UUID, undoManager: UndoManager?, actionName: String) {
        let before = byAccount[account] ?? []
        byAccount[account] = entries
        // An undo is a fresh rearrangement as far as other devices are concerned.
        orderChangedAt[account] = Date()
        save()
        registerUndo(to: before, account: account, undoManager: undoManager, actionName: actionName)
    }

    private func restoreMerged(_ entries: [MergedFavoriteRef], undoManager: UndoManager?, actionName: String) {
        let before = mergedOrder
        mergedOrder = entries
        saveMerged()
        registerMergedUndo(to: before, undoManager: undoManager, actionName: actionName)
    }

    private func registerUndo(to entries: [FavoriteRef], account: UUID, undoManager: UndoManager?, actionName: String) {
        guard let undoManager else { return }

        undoManager.registerUndo(withTarget: self) { store in
            store.restore(entries, account: account, undoManager: undoManager, actionName: actionName)
        }
        undoManager.setActionName(actionName)
    }

    private func registerMergedUndo(to entries: [MergedFavoriteRef], undoManager: UndoManager?, actionName: String) {
        guard let undoManager else { return }

        undoManager.registerUndo(withTarget: self) { store in
            store.restoreMerged(entries, undoManager: undoManager, actionName: actionName)
        }
        undoManager.setActionName(actionName)
    }

    /// Pushes the current order (and its per-account rearrange stamps, #739) up to
    /// iCloud, keyed by each account's stable sync id. No-op when iCloud is
    /// unavailable (#536).
    private func mirrorToCloud() {
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
        for (identity, cloudList) in cloud {
            guard let uuid = uuidForSyncID(identity),
                  let cloudStamp = cloudStamps[uuid],
                  cloudStamp > (orderChangedAt[uuid] ?? .distantPast) else { continue }

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
              cloudStamp > (mergedChangedAt ?? .distantPast),
              let data = CloudSyncStore.shared.data(forKey: Self.cloudMergedKey),
              let cloudRefs = try? JSONDecoder().decode([CloudMergedRef].self, from: data)
        else { return }

        let adopted: [MergedFavoriteRef] = cloudRefs.compactMap { entry in
            uuidForSyncID(entry.account).map { MergedFavoriteRef(account: $0, ref: entry.ref) }
        }
        guard adopted != mergedOrder else {
            mergedChangedAt = cloudStamp
            UserDefaults.standard.set(cloudStamp, forKey: Self.mergedStampKey)
            return
        }

        mergedOrder = adopted
        mergedChangedAt = cloudStamp
        saveMerged()
    }
}
