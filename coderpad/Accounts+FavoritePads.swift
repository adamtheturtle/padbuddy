//
//  Accounts+FavoritePads.swift
//  coderpad
//
//  Per-account favorite pads and pad-open tracking.
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
    private static let key = "favoritePads.v2"
    /// The iCloud mirror is keyed by each account's stable sync id (a `String`), not
    /// the per-device `UUID` the local blob uses, so it lives under its own key with
    /// its own schema (#536).
    private static let cloudKey = "favoritePads.cloud.v1"
    /// Held so the external-change observation task isn't cancelled; the store is a
    /// singleton that lives for the whole process, so it's never explicitly stopped.
    private var cloudObserverTask: Task<Void, Never>?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([UUID: [FavoritePad]].self, from: data) {
            byAccount = decoded
        }
        // Re-pull and merge whenever iCloud reports an external change to our mirror.
        cloudObserverTask = Task { @MainActor in
            for await note in NotificationCenter.default.notifications(named: CloudSyncStore.didChangeExternally) {
                guard note.userInfo?["key"] as? String == Self.cloudKey else { continue }

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
        var entries = byAccount[account] ?? []
        guard !entries.contains(where: { $0.id == id }) else { return }

        let before = entries
        entries.append(FavoritePad(id: id, title: title))
        byAccount[account] = entries
        save()
        registerUndo(to: before, account: account, undoManager: undoManager, actionName: "Add Favorite")
    }

    /// Toggles the pad's pinned state, appending when newly pinned so order holds.
    func toggle(_ id: String, title: String, account: UUID, undoManager: UndoManager? = nil) {
        var entries = byAccount[account] ?? []
        let before = entries
        let actionName: String
        if let index = entries.firstIndex(where: { $0.id == id }) {
            entries.remove(at: index)
            actionName = "Remove Favorite"
        } else {
            entries.append(FavoritePad(id: id, title: title))
            actionName = "Add Favorite"
        }
        byAccount[account] = entries
        save()
        registerUndo(to: before, account: account, undoManager: undoManager, actionName: actionName)
    }

    func remove(_ id: String, account: UUID, undoManager: UndoManager? = nil) {
        guard var entries = byAccount[account], let index = entries.firstIndex(where: { $0.id == id }) else { return }

        let before = entries
        entries.remove(at: index)
        byAccount[account] = entries
        save()
        registerUndo(to: before, account: account, undoManager: undoManager, actionName: "Remove Favorite")
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
            guard let title = titles[entries[index].id],
                  !title.isEmpty, title != entries[index].title else { continue }

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
        guard byAccount[account] != nil else { return }

        byAccount[account] = nil
        save()
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(byAccount)
            UserDefaults.standard.set(data, forKey: Self.key)
        } catch {
            let reason = error.localizedDescription
            persistenceLogger.error("Failed to encode favorite pads: \(reason, privacy: .public)")
        }
        mirrorToCloud()
    }

    private func restore(_ entries: [FavoritePad], account: UUID, undoManager: UndoManager?, actionName: String) {
        let before = byAccount[account] ?? []
        byAccount[account] = entries
        save()
        registerUndo(to: before, account: account, undoManager: undoManager, actionName: actionName)
    }

    private func registerUndo(to entries: [FavoritePad], account: UUID, undoManager: UndoManager?, actionName: String) {
        guard let undoManager else { return }

        undoManager.registerUndo(withTarget: self) { store in
            store.restore(entries, account: account, undoManager: undoManager, actionName: actionName)
        }
        undoManager.setActionName(actionName)
    }

    /// Pushes the current favourites up to iCloud, keyed by each account's stable sync
    /// id. No-op when iCloud is unavailable (#536).
    private func mirrorToCloud() {
        guard CloudSyncStore.shared.isAvailable else { return }

        let cloud = CloudSyncMerge.toCloud(byAccount) { uuid in
            AccountsStore.shared.accounts.first { $0.id == uuid }?.syncID
        }
        if let data = try? JSONEncoder().encode(cloud) {
            CloudSyncStore.shared.mirror(data, forKey: Self.cloudKey)
        }
    }

    /// Pulls the iCloud favourites and merges them into the local set (additive union
    /// per account), then persists. Called once accounts have loaded and on every
    /// external iCloud change. No-op when iCloud is unavailable (#536).
    func syncFromCloud() {
        guard let data = CloudSyncStore.shared.data(forKey: Self.cloudKey),
              let cloud = try? JSONDecoder().decode([String: [FavoritePad]].self, from: data) else { return }

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
        guard merged != byAccount else { return }

        byAccount = merged
        save()
    }
}

/// Per-account record of when each pad was last opened, so the pad list can show
/// an activity dot on a started pad that has changed *since you last looked at it*
/// — a more personal signal than "changed since the last background refresh".
/// Scoped per account (a pad id only means something within its org) and
/// persisted to UserDefaults as a single JSON blob keyed by account id.
@Observable
final class PadOpenedStore {
    static let shared = PadOpenedStore()
    private var byAccount: [UUID: [String: Date]] = [:]
    private static let key = "padLastOpened.v1"
    /// The iCloud mirror is keyed by each account's stable sync id, like the favourites
    /// mirror, so the activity-dot "last looked at" state follows the user across their
    /// Macs (#536).
    private static let cloudKey = "padLastOpened.cloud.v1"
    /// Held so the external-change observation task isn't cancelled; the store is a
    /// singleton that lives for the whole process, so it's never explicitly stopped.
    private var cloudObserverTask: Task<Void, Never>?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([UUID: [String: Date]].self, from: data) {
            byAccount = decoded
        }
        // Re-pull and merge whenever iCloud reports an external change to our mirror.
        cloudObserverTask = Task { @MainActor in
            for await note in NotificationCenter.default.notifications(named: CloudSyncStore.didChangeExternally) {
                guard note.userInfo?["key"] as? String == Self.cloudKey else { continue }

                Self.shared.syncFromCloud()
            }
        }
    }

    /// When the pad was last opened under this account, or `nil` if never opened.
    func lastOpened(_ padID: String, account: UUID?) -> Date? {
        guard let account else { return nil }

        return byAccount[account]?[padID]
    }

    /// Records that the pad was just opened, clearing its activity dot until it
    /// next changes. `now` is injectable for tests.
    func markOpened(_ padID: String, account: UUID, now: Date = Date()) {
        byAccount[account, default: [:]][padID] = now
        save()
    }

    /// Drops an account's open-history, called when the account is removed or
    /// re-keyed so its pad-open timestamps don't linger in UserDefaults (#379).
    func remove(account: UUID) {
        guard byAccount[account] != nil else { return }

        byAccount[account] = nil
        save()
    }

    /// Drops one pad's open timestamp under `account`, called by the central
    /// deletion cleanup so a deleted pad's record doesn't persist indefinitely
    /// (and reattach if the same id is ever seen again, #723).
    func removePad(_ padID: String, account: UUID) {
        guard byAccount[account]?[padID] != nil else { return }

        byAccount[account]?[padID] = nil
        save()
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(byAccount)
            UserDefaults.standard.set(data, forKey: Self.key)
        } catch {
            let reason = error.localizedDescription
            persistenceLogger.error("Failed to encode pad open times: \(reason, privacy: .public)")
        }
        mirrorToCloud()
    }

    /// Pushes the current open-history up to iCloud, keyed by each account's stable sync
    /// id. No-op when iCloud is unavailable (#536).
    private func mirrorToCloud() {
        guard CloudSyncStore.shared.isAvailable else { return }

        let cloud = CloudSyncMerge.toCloud(byAccount) { uuid in
            AccountsStore.shared.accounts.first { $0.id == uuid }?.syncID
        }
        if let data = try? JSONEncoder().encode(cloud) {
            CloudSyncStore.shared.mirror(data, forKey: Self.cloudKey)
        }
    }

    /// Pulls the iCloud open-history and merges it into the local set, keeping the most
    /// recent open per pad, then persists. Called once accounts have loaded and on every
    /// external iCloud change. No-op when iCloud is unavailable (#536).
    func syncFromCloud() {
        guard let data = CloudSyncStore.shared.data(forKey: Self.cloudKey),
              let cloud = try? JSONDecoder().decode([String: [String: Date]].self, from: data) else { return }

        let merged = CloudSyncMerge.mergeTimestamps(cloud: cloud, into: byAccount) { identity in
            AccountsStore.shared.accounts.first { $0.syncID == identity }?.id
        }
        guard merged != byAccount else { return }

        byAccount = merged
        save()
    }
}
