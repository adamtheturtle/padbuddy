//
//  FavoritesOrder.swift
//  coderpad
//
//  The single drag order that favourite pads and starred questions share in the
//  sidebar. Membership and titles still live in FavoritePadsStore and
//  FavoriteQuestionsStore; this records only the order the two kinds interleave in.
//

// swiftlint:disable file_length

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
    private static let logger = Logger(subsystem: "com.coderpad.app", category: "favorites-order")
    // Stored state and persistence keys are internal (not private) because the
    // iCloud mirroring half of the store lives in FavoritesOrder+Cloud.swift.
    var byAccount: [UUID: [FavoriteRef]] = [:]
    var mergedOrder: [MergedFavoriteRef] = []
    /// When each account's order was last rearranged on any device, so two Macs'
    /// orders can be reconciled last-reorder-wins: the plain array union always
    /// kept the local positions, so a drag on one Mac never landed on the other
    /// (#739). Mirrored to iCloud alongside the orders.
    var orderChangedAt: [UUID: Date] = [:]
    static let key = "favoritesOrder.v1"
    static let mergedKey = "favoritesMergedOrder.v1"
    static let stampsKey = "favoritesOrder.changedAt.v1"
    /// When the merged (cross-account) order was last rearranged on any device,
    /// so devices reconcile it last-reorder-wins like the per-account orders (#1151).
    var mergedChangedAt: Date?
    /// The iCloud mirror, keyed by each account's stable sync id rather than the
    /// per-device `UUID`, under its own key (#536).
    static let cloudKey = "favoritesOrder.cloud.v1"
    static let cloudStampsKey = "favoritesOrder.changedAt.cloud.v1"
    static let mergedStampKey = "favoritesMergedOrder.changedAt.v1"
    static let cloudMergedKey = "favoritesMergedOrder.cloud.v1"
    static let cloudMergedStampKey = "favoritesMergedOrder.changedAt.cloud.v1"
    /// singleton that lives for the whole process, so it's never explicitly stopped.
    /// singleton that lives for the whole process, so it is never explicitly stopped.
    private var cloudObserverTask: Task<Void, Never>?

    /// The last reconciliation for each account, and for the merged view, so a
    /// re-read with unchanged inputs returns the previous result instead of
    /// rebuilding it. Reconciliation allocates two `Set`s and runs two filter passes,
    /// and the sidebar reads it on every render — for favourites that changed only
    /// when one was added, removed, or dragged (#2113). Observation-ignored: these are
    /// a memo of state the sidebar already observes, and publishing writes made from
    /// inside a `body` read would invalidate the very view that took the reading.
    @ObservationIgnored var orderMemos: [UUID: OrderMemo<FavoriteRef>] = [:]
    @ObservationIgnored var mergedMemo: OrderMemo<MergedFavoriteRef>?

    /// One cached reconciliation, alongside the two inputs it was derived from.
    struct OrderMemo<Ref: Hashable> {
        let present: [Ref]
        let stored: [Ref]
        let result: [Ref]
    }

    /// Sanity caps for the persisted and mirrored blobs (#1788): more refs than a
    /// sidebar could ever hold means corrupt or injected data, and decoding it
    /// verbatim would burn launch memory, sidebar work, and cloud writes.
    static let maxOrderEntriesPerAccount = 1000
    static let maxMergedOrderEntries = 2000

    static func decodePersisted<Value: Decodable>(
        _ type: Value.Type,
        key: String,
        defaults: UserDefaults = .standard
    ) -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }

        do {
            return try SharedCoders.decoder.decode(type, from: data)
        } catch {
            logger.error("Discarding corrupt favorites order for \(key, privacy: .public): \(error)")
            defaults.removeObject(forKey: key)
            return nil
        }
    }

    private init() {
        if let decoded = Self.decodePersisted([UUID: [FavoriteRef]].self, key: Self.key) {
            byAccount = decoded.mapValues { Array($0.prefix(Self.maxOrderEntriesPerAccount)) }
        }
        if let decoded = Self.decodePersisted([MergedFavoriteRef].self, key: Self.mergedKey) {
            mergedOrder = Array(decoded.prefix(Self.maxMergedOrderEntries))
        }
        if let decoded = Self.decodePersisted([UUID: Date].self, key: Self.stampsKey) {
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

        let stored = byAccount[account] ?? []
        if let memo = orderMemos[account], memo.present == present, memo.stored == stored {
            return memo.result
        }

        let result = Self.reconcile(stored: stored, present: present)
        orderMemos[account] = OrderMemo(present: present, stored: stored, result: result)
        return result
    }

    /// Stored refs that are still present, in their saved order, then the rest of
    /// `present` in its own order.
    ///
    /// Deduplicated while filtering: a corrupt or legacy stored array with repeated
    /// refs must not hand the sidebar duplicate row identities (#1782, #1783).
    static func reconcile<Ref: Hashable>(stored: [Ref], present: [Ref]) -> [Ref] {
        let presentSet = Set(present)
        var seen = Set<Ref>()
        var result = stored.filter { presentSet.contains($0) && seen.insert($0).inserted }
        result.append(contentsOf: present.filter { !seen.contains($0) })
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

        // Snapshot the *reconciled* order, not the raw stored array. `ordered`
        // includes favourites that are present but not yet recorded in `byAccount`
        // (anything added since the last drag), so undoing against the raw array
        // restored an order missing them — and the read-time reconciliation then
        // re-appended them at the end instead of where they had been (#2508, #2509).
        let before = ordered
        ordered.remove(at: from)
        let insertAt = ordered.firstIndex(of: target) ?? ordered.count
        ordered.insert(ref, at: insertAt)
        byAccount[account] = ordered
        orderChangedAt[account] = Date()
        save()
        registerUndo(to: before, account: account, undoManager: undoManager,
                     actionName: String(localized: "Move Favorite"))
    }

    /// Moves `ref` to the end of the combined order. This backs drops into the empty
    /// space below the final favorite row, where there is no row to use as a `before`
    /// target.
    func moveToEnd(_ ref: FavoriteRef, present: [FavoriteRef], account: UUID, undoManager: UndoManager? = nil) {
        var ordered = order(present: present, account: account)
        guard let from = ordered.firstIndex(of: ref), let last = ordered.indices.last, from != last else { return }

        // Snapshot the *reconciled* order, not the raw stored array. `ordered`
        // includes favourites that are present but not yet recorded in `byAccount`
        // (anything added since the last drag), so undoing against the raw array
        // restored an order missing them — and the read-time reconciliation then
        // re-appended them at the end instead of where they had been (#2508, #2509).
        let before = ordered
        ordered.remove(at: from)
        ordered.append(ref)
        byAccount[account] = ordered
        orderChangedAt[account] = Date()
        save()
        registerUndo(to: before, account: account, undoManager: undoManager,
                     actionName: String(localized: "Move Favorite"))
    }

    /// Restores the natural membership order (pads, then questions) while keeping the
    /// operation undoable and cloud-synchronized.
    func reset(present: [FavoriteRef], account: UUID, undoManager: UndoManager? = nil) {
        let before = order(present: present, account: account)
        guard before != present else { return }

        byAccount[account] = present
        orderChangedAt[account] = Date()
        save()
        registerUndo(to: before, account: account, undoManager: undoManager,
                     actionName: String(localized: "Restore Favorite Order"))
    }

    /// The combined-view favourites in their stored cross-account order. This is separate
    /// from the per-account order above because merged rows can be dragged across accounts.
    func merged(present: [MergedFavoriteRef]) -> [MergedFavoriteRef] {
        if let memo = mergedMemo, memo.present == present, memo.stored == mergedOrder {
            return memo.result
        }

        let result = Self.reconcile(stored: mergedOrder, present: present)
        mergedMemo = OrderMemo(present: present, stored: mergedOrder, result: result)
        return result
    }

    func moveMerged(_ ref: MergedFavoriteRef, before target: MergedFavoriteRef, present: [MergedFavoriteRef],
                    undoManager: UndoManager? = nil) {
        guard ref != target else { return }

        var ordered = merged(present: present)
        guard let from = ordered.firstIndex(of: ref), ordered.contains(target) else { return }

        // The reconciled order, for the same reason as the per-account moves above:
        // `mergedOrder` omits favourites that are present but not yet recorded, so
        // undoing against it appended them rather than restoring their positions (#2510).
        let before = ordered
        ordered.remove(at: from)
        let insertAt = ordered.firstIndex(of: target) ?? ordered.count
        ordered.insert(ref, at: insertAt)
        mergedOrder = ordered
        mergedChangedAt = Date()
        saveMerged()
        registerMergedUndo(to: before, undoManager: undoManager, actionName: String(localized: "Move Favorite"))
    }

    func moveMergedToEnd(_ ref: MergedFavoriteRef, present: [MergedFavoriteRef], undoManager: UndoManager? = nil) {
        var ordered = merged(present: present)
        guard let from = ordered.firstIndex(of: ref), let last = ordered.indices.last, from != last else { return }

        // The reconciled order, for the same reason as the per-account moves above:
        // `mergedOrder` omits favourites that are present but not yet recorded, so
        // undoing against it appended them rather than restoring their positions (#2510).
        let before = ordered
        ordered.remove(at: from)
        ordered.append(ref)
        mergedOrder = ordered
        mergedChangedAt = Date()
        saveMerged()
        registerMergedUndo(to: before, undoManager: undoManager, actionName: String(localized: "Move Favorite"))
    }

    func resetMerged(present: [MergedFavoriteRef], undoManager: UndoManager? = nil) {
        let before = merged(present: present)
        guard before != present else { return }

        mergedOrder = present
        mergedChangedAt = Date()
        saveMerged()
        registerMergedUndo(to: before, undoManager: undoManager,
                           actionName: String(localized: "Restore Favorite Order"))
    }

    /// This account's saved order and its slice of the merged order, for a caller that
    /// is about to `forget` a ref and wants to be able to put it back.
    struct OrderSnapshot {
        let account: [FavoriteRef]
        let merged: [MergedFavoriteRef]
    }

    func snapshot(account: UUID) -> OrderSnapshot {
        OrderSnapshot(account: byAccount[account] ?? [], merged: mergedOrder)
    }

    /// Puts back a snapshot taken before a `forget`, so undoing an unfavourite returns
    /// the item to the slot it was dragged into rather than appending it (#2511, #2512).
    func restore(_ snapshot: OrderSnapshot, account: UUID) {
        guard byAccount[account] ?? [] != snapshot.account || mergedOrder != snapshot.merged else { return }

        byAccount[account] = snapshot.account.isEmpty ? nil : snapshot.account
        orderChangedAt[account] = Date()
        mergedOrder = snapshot.merged
        mergedChangedAt = Date()
        save()
        saveMerged()
    }

    /// Forgets one favourite's saved position, called when it is unfavourited.
    ///
    /// Read-time reconciliation already hides a ref whose item is no longer a
    /// favourite, so nothing looked wrong — but the ref stayed in defaults and in the
    /// iCloud mirror forever, and re-favouriting the same pad or question silently
    /// restored its old position instead of appending it as new (#2511, #2512).
    ///
    /// The unfavourite that triggers this captures an `OrderSnapshot` first and hands
    /// it to its undo, so undoing restores the position rather than appending.
    func forget(_ ref: FavoriteRef, account: UUID) {
        let hadAccountEntry = byAccount[account]?.contains(ref) == true
        let mergedRef = MergedFavoriteRef(account: account, ref: ref)
        let filteredMerged = mergedOrder.filter { $0 != mergedRef }
        guard hadAccountEntry || filteredMerged.count != mergedOrder.count else { return }

        if hadAccountEntry {
            byAccount[account] = byAccount[account]?.filter { $0 != ref }
            orderChangedAt[account] = Date()
            save()
        }
        if filteredMerged.count != mergedOrder.count {
            mergedOrder = filteredMerged
            mergedChangedAt = Date()
            saveMerged()
        }
    }

    /// Drops an account's saved order, called when the account is removed or re-keyed so
    /// its favourite refs don't linger in UserDefaults, alongside the kind-specific
    /// stores (#379). `syncID` is the removed account's stable sync identity: the
    /// cloud merge is additive, so without an explicit cloud delete other devices
    /// keep the old order and can restore it when the same identity returns (#1150).
    func remove(account: UUID, syncID: String? = nil) {
        if let syncID {
            removeFromCloud(syncID: syncID)
        }

        let hadAccountOrder = byAccount[account] != nil
        let filteredMergedOrder = mergedOrder.filter { $0.account != account }
        guard hadAccountOrder || filteredMergedOrder.count != mergedOrder.count else { return }

        byAccount[account] = nil
        orderChangedAt[account] = nil
        // The memo would invalidate itself on the next read anyway; dropping it here
        // keeps a long-lived process from holding one per removed account (#2113).
        orderMemos[account] = nil
        mergedOrder = filteredMergedOrder
        // The merged order is reconciled last-reorder-wins against this stamp, so leaving
        // it at its pre-removal value let the mirrored copy compare as newer and merge the
        // removed account's refs straight back in — on another device, or here on the next
        // `syncFromCloud()`. `forget(_:account:)` bumps it in exactly this situation
        // (#4716).
        mergedChangedAt = Date()
        save()
        saveMerged()
    }

    func save() {
        do {
            let data = try SharedCoders.encoder.encode(byAccount)
            UserDefaults.standard.set(data, forKey: Self.key)
            let stamps = try SharedCoders.encoder.encode(orderChangedAt)
            UserDefaults.standard.set(stamps, forKey: Self.stampsKey)
        } catch {
            let reason = error.localizedDescription
            persistenceLogger.error("Failed to encode favorites order: \(reason, privacy: .public)")
        }
        mirrorToCloud()
    }

    func saveMerged() {
        do {
            let data = try SharedCoders.encoder.encode(mergedOrder)
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
        // An undo is a fresh rearrangement as far as other devices are concerned, as the
        // per-account `restore` already treats it. Without the bump the stamp still names
        // the reorder being undone, so the mirrored post-reorder copy compares as newer
        // and the undo is reverted at the next cloud reconciliation (#4717).
        mergedChangedAt = Date()
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
}

// The iCloud mirroring/reconciliation half of the store - mirrorToCloud,
// syncFromCloud, and the removed-account cloud cleanup - lives in
// FavoritesOrder+Cloud.swift to keep this file within the length lint.
