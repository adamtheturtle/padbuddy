//
//  Accounts+FavoritePads.swift
//  coderpad
//
//  Per-account favorite pads. Pad-open tracking lives in Accounts+PadOpened.swift.
//

import Foundation
import os
import SwiftUI

/// One favorite ("pinned") pad: its CoderPad slug id plus the title captured when it
/// was pinned. Persisting the title lets the sidebar show the pad's name immediately
/// — even before the pads list has loaded — instead of falling back to the bare slug
/// / short code (#654), mirroring how a starred question keeps its title (#325).
struct FavoritePad: Codable, Hashable {
    let id: String
    var title: String
    /// When this favorite was (re-)pinned, so a deletion tombstone from another
    /// device can be ordered against it (#738). Optional so entries persisted
    /// before it existed still decode; they count as arbitrarily old.
    var addedAt: Date?
}

/// Per-account favorite ("pinned") pads, identified by pad id. The pad counterpart
/// to ``FavoriteQuestionsStore``: dragging a pad onto the sidebar pins it as a
/// quick-access shortcut. Scoped per account — a pad id is a CoderPad slug, unique
/// across orgs, but favorites are still kept per account so the sidebar shows the
/// right set — and persisted to UserDefaults as one JSON blob keyed by account id.
/// The array keeps insertion order so the sidebar lists pads in the order pinned.
/// Each entry also carries the pad's title (see ``FavoritePad``) so the sidebar never
/// has to fall back to its bare slug (#654).
@Observable
final class FavoritePadsStore {
    static let shared = FavoritePadsStore()
    private var byAccount: [UUID: [FavoritePad]] = [:]
    /// Dated per-account deletion tombstones, so an unfavorite converges across
    /// devices instead of being unioned back by another Mac's mirror (#738).
    private var removedAt: [UUID: [String: Date]] = [:]
    private static let key = "favoritePads.v2"
    private static let tombstonesKey = "favoritePads.tombstones.v1"
    /// The iCloud mirror is keyed by each account's stable sync id (a `String`), not
    /// the per-device `UUID` the local blob uses, so it lives under its own key with
    /// its own schema (#536).
    private static let cloudKey = "favoritePads.cloud.v1"
    private static let cloudTombstonesKey = "favoritePads.tombstones.cloud.v1"
    /// Held so the external-change observation task isn't cancelled; the store is a
    /// singleton that lives for the whole process, so it's never explicitly stopped.
    private var cloudObserverTask: Task<Void, Never>?

    /// Sanity caps for the persisted and mirrored favorites (#1788): more entries
    /// than a sidebar could ever show, or titles far past any real pad name, mean
    /// corrupt or injected data - decoding them verbatim would burn launch
    /// memory, sidebar work, and cloud writes.
    static let maxEntriesPerAccount = 500
    static let maxTitleLength = 256

    /// Clamps a decoded entries array to the sanity caps (#1788).
    private static func sanitized(_ entries: [FavoritePad]) -> [FavoritePad] {
        // De-duplicate by id first. Decoded data was trusted as-is, so a blob that
        // had picked up a repeat — from a bad merge, a restore, or an older build —
        // produced two sidebar rows for one pad, made `toggle` remove only one of
        // them, and left tombstone resolution ambiguous (#2528). First occurrence
        // wins, which keeps the pinned order the user arranged.
        var seen = Set<String>()
        return entries
            .filter { seen.insert($0.id).inserted }
            .prefix(maxEntriesPerAccount)
            .map { entry in
                var entry = entry
                if entry.title.count > maxTitleLength {
                    entry.title = String(entry.title.prefix(maxTitleLength))
                }
                return entry
            }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([UUID: [FavoritePad]].self, from: data) {
            byAccount = decoded.mapValues(Self.sanitized)
        }
        if let data = UserDefaults.standard.data(forKey: Self.tombstonesKey),
           let decoded = try? JSONDecoder().decode([UUID: [String: Date]].self, from: data) {
            removedAt = decoded
        }
        // Re-pull and merge whenever iCloud reports an external change to our mirror.
        cloudObserverTask = Task { @MainActor in
            for await note in NotificationCenter.default.notifications(named: CloudSyncStore.didChangeExternally) {
                // The tombstone blob changes independently of the membership blob: a
                // remote unfavourite writes only the former. Watching just the
                // membership key left that removal unreconciled — the favourite stayed
                // in the sidebar until some unrelated change happened to rewrite the
                // membership blob as well (#2525, #2526).
                let key = note.userInfo?["key"] as? String
                guard key == Self.cloudKey || key == Self.cloudTombstonesKey else { continue }

                Self.shared.syncFromCloud()
            }
        }
    }

    /// The favorite pad ids in pinned order, for membership tests and ordering — the
    /// callers that only care about identity, not titles.
    func favorites(account: UUID?) -> [String] {
        guard let account else { return [] }

        return (byAccount[account] ?? []).map(\.id)
    }

    /// The favorite pads with their stored titles, in pinned order, for the sidebar
    /// rows that show a name.
    func titledFavorites(account: UUID?) -> [FavoritePad] {
        guard let account else { return [] }

        return byAccount[account] ?? []
    }

    func isFavorite(_ id: String, account: UUID?) -> Bool {
        guard let account else { return false }

        return byAccount[account]?.contains { $0.id == id } ?? false
    }

    /// Pins the pad if it isn't already, preserving order. Used by the sidebar drop
    /// target, where a drop should only ever add (never remove) a favorite.
    func add(_ id: String, title: String, account: UUID, undoManager: UndoManager? = nil) {
        // A drop payload is just a string. An empty or whitespace-only one can never
        // resolve to a pad, so it would persist as an unusable sidebar row that pad
        // cleanup never touches, because there is no pad for it to match (#2520).
        let padID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !padID.isEmpty else { return }

        var entries = byAccount[account] ?? []
        let before = entries
        if let index = entries.firstIndex(where: { $0.id == padID }) {
            // Already pinned. Returning here meant dropping a renamed pad onto
            // Favorites couldn't correct its captured title, which stayed stale until
            // an unrelated cache refresh happened along (#2522). Take the newer title
            // and leave `addedAt` alone — this is not a new pin.
            guard entries[index].title != title else { return }

            entries[index].title = title
        } else {
            entries.append(FavoritePad(id: padID, title: title, addedAt: Date()))
        }
        byAccount[account] = entries
        save()
        registerUndo(to: before, account: account, undoManager: undoManager, actionName: "Add Favorite")
    }

    /// Toggles the pad's pinned state, appending when newly pinned so order holds.
    func toggle(_ id: String, title: String, account: UUID, undoManager: UndoManager? = nil) {
        var entries = byAccount[account] ?? []
        let before = entries
        let actionName: String
        // Captured before the branch so an unfavourite can hand it to its undo; a
        // favourite that isn't removed leaves the order untouched, so it costs nothing.
        let order = FavoritesOrderStore.shared.snapshot(account: account)
        if let index = entries.firstIndex(where: { $0.id == id }) {
            entries.remove(at: index)
            recordRemoval(of: id, account: account)
            // Same as `remove`: the saved drag position goes with the favourite (#2511, #2512).
            FavoritesOrderStore.shared.forget(FavoriteRef.pad(id), account: account)
            actionName = "Remove Favorite"
        } else {
            entries.append(FavoritePad(id: id, title: title, addedAt: Date()))
            actionName = "Add Favorite"
        }
        byAccount[account] = entries
        save()
        registerUndo(to: before, account: account, undoManager: undoManager,
                     actionName: actionName, order: order)
    }

    func remove(_ id: String, account: UUID, undoManager: UndoManager? = nil) {
        guard var entries = byAccount[account], let index = entries.firstIndex(where: { $0.id == id }) else { return }

        let before = entries
        entries.remove(at: index)
        byAccount[account] = entries
        recordRemoval(of: id, account: account)
        // Drop the saved drag position too. Reconciliation hid the stale ref, but it
        // stayed in defaults and iCloud forever and silently restored the old position
        // if this was ever favourited again (#2511, #2512). The snapshot lets undo put
        // it back where it was rather than appending it.
        let order = FavoritesOrderStore.shared.snapshot(account: account)
        FavoritesOrderStore.shared.forget(FavoriteRef.pad(id), account: account)
        save()
        registerUndo(to: before, account: account, undoManager: undoManager,
                     actionName: "Remove Favorite", order: order)
    }

    /// Reorders `id` to sit immediately before `targetID`, persisting the new order
    /// (drag-to-reorder in the sidebar, #299). A no-op if either id isn't present.
    func move(_ id: String, before targetID: String, account: UUID, undoManager: UndoManager? = nil) {
        var entries = byAccount[account] ?? []
        guard let from = entries.firstIndex(where: { $0.id == id }),
              entries.contains(where: { $0.id == targetID }), id != targetID else { return }

        let before = entries
        let moved = entries.remove(at: from)
        let insertAt = entries.firstIndex(where: { $0.id == targetID }) ?? entries.count
        entries.insert(moved, at: insertAt)
        byAccount[account] = entries
        save()
        registerUndo(to: before, account: account, undoManager: undoManager, actionName: "Move Favorite")
    }

    /// Updates stored titles from a freshly loaded pad list, so a favourite's name
    /// stays current after a rename (and a pad favourited while still untitled gains
    /// its name once set). Called when an account's pads cache is refreshed; a no-op
    /// when nothing actually changed, so it doesn't churn the store on every load.
    func refreshTitles(from pads: [Pad], account: UUID) {
        guard var entries = byAccount[account], !entries.isEmpty else { return }

        let titles = Dictionary(
            pads.map { ($0.id, $0.title) },
            uniquingKeysWith: { first, _ in first }
        )
        var changed = false
        for index in entries.indices {
            // A cleared title propagates. Blank titles used to be skipped so a
            // usable stored label wasn't replaced by a blank sidebar row (#1786),
            // but the sidebar now treats a blank stored title as absent and falls
            // back to the live cache title and then the pad's slug (#1680, #1681) —
            // so the row stays readable either way, and keeping the old text meant
            // showing a name the server no longer has (#2524).
            guard let title = titles[entries[index].id], title != entries[index].title else { continue }

            entries[index].title = title
            changed = true
        }
        guard changed else { return }

        byAccount[account] = entries
        save()
    }

    /// Drops every favorite for an account, called when the account is removed or
    /// re-keyed so its pinned pad ids don't linger in UserDefaults (#379).
    func remove(account: UUID) {
        guard byAccount[account] != nil || removedAt[account] != nil else { return }

        byAccount[account] = nil
        removedAt[account] = nil
        save()
    }

    /// Records a dated deletion tombstone so the removal propagates through the
    /// additive iCloud merge instead of being unioned back (#738).
    private func recordRemoval(of id: String, account: UUID) {
        removedAt[account, default: [:]][id] = Date()
    }

    private func save() {
        // A present id retires its tombstone (re-added locally, incl. via undo),
        // and old tombstones age out so the map stays bounded.
        for (account, entries) in byAccount {
            guard var tombstones = removedAt[account] else { continue }

            for entry in entries {
                tombstones[entry.id] = nil
            }
            removedAt[account] = CloudTombstones.pruned(tombstones)
        }
        do {
            let data = try JSONEncoder().encode(byAccount)
            UserDefaults.standard.set(data, forKey: Self.key)
            let tombstones = try JSONEncoder().encode(removedAt)
            UserDefaults.standard.set(tombstones, forKey: Self.tombstonesKey)
        } catch {
            let reason = error.localizedDescription
            persistenceLogger.error("Failed to encode favorite pads: \(reason, privacy: .public)")
        }
        mirrorToCloud()
    }

    private func restore(_ entries: [FavoritePad], account: UUID, undoManager: UndoManager?, actionName: String) {
        let before = byAccount[account] ?? []
        // Anything the restore drops relative to the current list is a removal to
        // propagate; anything it (re-)introduces is stamped as freshly added so it
        // beats any remote tombstone (#738).
        let restoredIDs = Set(entries.map(\.id))
        for entry in before where !restoredIDs.contains(entry.id) {
            recordRemoval(of: entry.id, account: account)
        }
        // Only entries the restore actually brings back are restamped. Restamping
        // every entry made unrelated old favourites look newly added, so they beat
        // remote deletion tombstones and reappeared on other devices after an
        // undo that had nothing to do with them (#2527).
        let presentIDs = Set(before.map(\.id))
        let now = Date()
        byAccount[account] = entries.map { entry in
            guard !presentIDs.contains(entry.id) else { return entry }

            var entry = entry
            entry.addedAt = now
            return entry
        }
        save()
        registerUndo(to: before, account: account, undoManager: undoManager, actionName: actionName)
    }

    private func registerUndo(to entries: [FavoritePad], account: UUID, undoManager: UndoManager?,
                              actionName: String,
                              order: FavoritesOrderStore.OrderSnapshot? = nil) {
        guard let undoManager else { return }

        undoManager.registerUndo(withTarget: self) { store in
            // Order first: `restore` re-adds the membership, and the sidebar
            // reconciles against whatever order is in place at that moment.
            if let order { FavoritesOrderStore.shared.restore(order, account: account) }
            store.restore(entries, account: account, undoManager: undoManager, actionName: actionName)
        }
        undoManager.setActionName(actionName)
    }

    /// Pushes the current favourites (and their deletion tombstones, #738) up to
    /// iCloud, keyed by each account's stable sync id. No-op when iCloud is
    /// unavailable (#536).
    private func mirrorToCloud() {
        guard CloudSyncStore.shared.isAvailable else { return }

        // Indexed once rather than scanned per account (#2439).
        let syncIDs = AccountsStore.shared.syncIDsByAccountID
        let syncID: (UUID) -> String? = { syncIDs[$0] }
        if let data = try? JSONEncoder().encode(CloudSyncMerge.toCloud(byAccount, syncID: syncID)) {
            CloudSyncStore.shared.mirror(data, forKey: Self.cloudKey)
        }
        if let data = try? JSONEncoder().encode(CloudSyncMerge.toCloud(removedAt, syncID: syncID)) {
            CloudSyncStore.shared.mirror(data, forKey: Self.cloudTombstonesKey)
        }
    }

    /// Pulls the iCloud favourites and merges them into the local set (additive union
    /// per account), then resolves deletion tombstones so an unfavorite made on
    /// another Mac converges here instead of being unioned back (#738), and persists.
    /// Called once accounts have loaded and on every external iCloud change. No-op
    /// when iCloud is unavailable (#536).
    func syncFromCloud() {
        guard let data = CloudSyncStore.shared.data(forKey: Self.cloudKey),
              let decoded = try? JSONDecoder().decode([String: [FavoritePad]].self, from: data) else { return }

        // The mirror is cross-device input: clamp it like the local blob (#1788).
        let cloud = decoded.mapValues(Self.sanitized)

        let uuidForSyncID: (String) -> UUID? = { identity in
            AccountsStore.shared.accounts.first { $0.syncID == identity }?.id
        }
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
           let cloudTombstones = try? JSONDecoder().decode([String: [String: Date]].self, from: data) {
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
        save()
    }
}
