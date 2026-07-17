//
//  Accounts+FavoriteQuestions.swift
//  coderpad
//
//  Per-account favorite ("starred") questions.
//  Kept in its own file so each stays within its length budget (#536).
//

import Foundation
import os
import SwiftUI

/// One starred question: its per-org id plus the title captured when it was
/// favorited. Persisting the title lets the sidebar show the question's name
/// immediately — even before the questions list has loaded — instead of a
/// "Question #id" placeholder (#325).
struct FavoriteQuestion: Codable, Hashable {
    let id: Int
    var title: String
}

/// Per-account favorite ("starred") questions, identified by question id. A
/// favorite is a quick-access marker: starred questions float to the top of the
/// Questions list and lead the menu bar's "New Pad from Question" submenu, so a
/// frequently used question is one click away from a fresh pad. Scoped per
/// account — a question id only means something within the org that owns it — and
/// persisted to UserDefaults as a single JSON blob keyed by account id. The
/// stored array keeps insertion order so the menu bar can lead with the questions
/// the user starred first. Each entry also carries the question's title (see
/// ``FavoriteQuestion``) so the sidebar never has to fall back to its bare id.
@Observable
final class FavoriteQuestionsStore {
    static let shared = FavoriteQuestionsStore()
    private var byAccount: [UUID: [FavoriteQuestion]] = [:]
    private static let key = "favoriteQuestions.v2"
    private static let legacyKey = "favoriteQuestions.v1"
    /// The iCloud mirror, keyed by each account's stable sync id rather than the
    /// per-device `UUID`, under its own key (#536).
    private static let cloudKey = "favoriteQuestions.cloud.v1"
    private var cloudObserver: (any NSObjectProtocol)?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([UUID: [FavoriteQuestion]].self, from: data) {
            byAccount = decoded
        } else if let data = UserDefaults.standard.data(forKey: Self.legacyKey),
                  let legacy = try? JSONDecoder().decode([UUID: [Int]].self, from: data) {
            // Carry id-only favorites saved before titles were stored into the new
            // shape with empty titles; they're backfilled from the cache by
            // `refreshTitles` as soon as the account's questions load.
            byAccount = legacy.mapValues { ids in ids.map { FavoriteQuestion(id: $0, title: "") } }
            save()
            UserDefaults.standard.removeObject(forKey: Self.legacyKey)
        }
        cloudObserver = NotificationCenter.default.addObserver(
            forName: CloudSyncStore.didChangeExternally, object: nil, queue: .main
        ) { note in
            let key = note.userInfo?["key"] as? String
            // Delivered on the main queue, so we're already on the main actor.
            MainActor.assumeIsolated {
                guard key == Self.cloudKey else { return }

                Self.shared.syncFromCloud()
            }
        }
    }

    /// The favorite question ids in starred order, for membership tests, sorting,
    /// and the menu bar — the callers that only care about identity, not titles.
    func favorites(account: UUID?) -> [Int] {
        guard let account else { return [] }

        return (byAccount[account] ?? []).map(\.id)
    }

    /// The favorite questions with their stored titles, in starred order, for the
    /// sidebar rows that show a name.
    func titledFavorites(account: UUID?) -> [FavoriteQuestion] {
        guard let account else { return [] }

        return byAccount[account] ?? []
    }

    func isFavorite(_ id: Int, account: UUID?) -> Bool {
        guard let account else { return false }

        return byAccount[account]?.contains { $0.id == id } ?? false
    }

    /// Adds the question to favorites if absent, removes it if present. New
    /// favorites append to the end so the existing order is preserved.
    func toggle(_ id: Int, title: String, account: UUID, undoManager: UndoManager? = nil) {
        var entries = byAccount[account] ?? []
        let before = entries
        let actionName: String
        if let index = entries.firstIndex(where: { $0.id == id }) {
            entries.remove(at: index)
            actionName = "Remove Favorite"
        } else {
            entries.append(FavoriteQuestion(id: id, title: title))
            actionName = "Add Favorite"
        }
        byAccount[account] = entries
        save()
        // Keep the New Pad widget button's question picker in step with this account's
        // favourites.
        WidgetSync.syncFavorites(account: account)
        registerUndo(to: before, account: account, undoManager: undoManager, actionName: actionName)
    }

    /// Favorites the question if it isn't already, preserving order. Used by the
    /// sidebar drop target, where a drop should only ever add a favorite (never
    /// remove one), so a no-op when it's already starred.
    func add(_ id: Int, title: String, account: UUID, undoManager: UndoManager? = nil) {
        var entries = byAccount[account] ?? []
        guard !entries.contains(where: { $0.id == id }) else { return }

        let before = entries
        entries.append(FavoriteQuestion(id: id, title: title))
        byAccount[account] = entries
        save()
        WidgetSync.syncFavorites(account: account)
        registerUndo(to: before, account: account, undoManager: undoManager, actionName: "Add Favorite")
    }

    /// Reorders `id` to sit immediately before `targetID`, persisting the new order
    /// (drag-to-reorder in the sidebar, #299). A no-op if either id isn't present.
    func move(_ id: Int, before targetID: Int, account: UUID, undoManager: UndoManager? = nil) {
        var entries = byAccount[account] ?? []
        guard let from = entries.firstIndex(where: { $0.id == id }),
              entries.contains(where: { $0.id == targetID }), id != targetID else { return }

        let before = entries
        let moved = entries.remove(at: from)
        let insertAt = entries.firstIndex(where: { $0.id == targetID }) ?? entries.count
        entries.insert(moved, at: insertAt)
        byAccount[account] = entries
        save()
        WidgetSync.syncFavorites(account: account)
        registerUndo(to: before, account: account, undoManager: undoManager, actionName: "Move Favorite")
    }

    /// Drops every starred question for an account, called when the account is
    /// removed or re-keyed so its question ids and captured titles don't linger in
    /// UserDefaults — the titles can carry candidate names, a privacy concern (#379).
    func remove(account: UUID) {
        guard byAccount[account] != nil else { return }

        byAccount[account] = nil
        save()
        // Push the now-empty favorites to the widget so its question picker drops them too.
        WidgetSync.syncFavorites(account: account)
    }

    /// Removes one starred question under `account` if present, called by the
    /// central deletion cleanup so a deleted question can't linger as a dead
    /// sidebar shortcut or New Pad seed (#722). Unlike `toggle`, never adds.
    func remove(_ id: Int, account: UUID, undoManager: UndoManager? = nil) {
        guard var entries = byAccount[account], let index = entries.firstIndex(where: { $0.id == id }) else { return }

        let before = entries
        entries.remove(at: index)
        byAccount[account] = entries
        save()
        WidgetSync.syncFavorites(account: account)
        registerUndo(to: before, account: account, undoManager: undoManager, actionName: "Remove Favorite")
    }

    /// Updates stored titles from a freshly loaded question list, so a favorite's
    /// name stays current after a rename and legacy id-only favorites gain a title.
    /// Called when an account's questions cache is refreshed; a no-op when nothing
    /// actually changed, so it doesn't churn the store on every load.
    func refreshTitles(from questions: [Question], account: UUID) {
        guard var entries = byAccount[account], !entries.isEmpty else { return }

        let titles = Dictionary(
            questions.map { ($0.id, $0.displayTitle) },
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
        WidgetSync.syncFavorites(account: account)
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(byAccount)
            UserDefaults.standard.set(data, forKey: Self.key)
        } catch {
            let reason = error.localizedDescription
            persistenceLogger.error("Failed to encode favorite questions: \(reason, privacy: .public)")
        }
        mirrorToCloud()
    }

    private func restore(_ entries: [FavoriteQuestion], account: UUID, undoManager: UndoManager?, actionName: String) {
        let before = byAccount[account] ?? []
        byAccount[account] = entries
        save()
        WidgetSync.syncFavorites(account: account)
        registerUndo(to: before, account: account, undoManager: undoManager, actionName: actionName)
    }

    private func registerUndo(to entries: [FavoriteQuestion], account: UUID,
                              undoManager: UndoManager?, actionName: String) {
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

    /// Pulls the iCloud favourites and merges them into the local set, unioning by
    /// question id so a title backfilled on only one device never forks an entry, then
    /// persists. Called once accounts have loaded and on every external iCloud change.
    /// No-op when iCloud is unavailable (#536).
    func syncFromCloud() {
        guard let data = CloudSyncStore.shared.data(forKey: Self.cloudKey),
              let cloud = try? JSONDecoder().decode([String: [FavoriteQuestion]].self, from: data) else { return }

        let uuidForSyncID: (String) -> UUID? = { identity in
            AccountsStore.shared.accounts.first { $0.syncID == identity }?.id
        }
        var merged = CloudSyncMerge.mergeArrays(cloud: cloud, into: byAccount,
                                                uuidForSyncID: uuidForSyncID) { $0.id }
        // The union keeps the local element for ids on both sides, so also adopt
        // titles renamed on another Mac (#762).
        merged = FavoriteTitleSync.adoptCloudTitles(
            merged: merged, cloud: cloud, uuidForSyncID: uuidForSyncID,
            id: { $0.id }, title: { $0.title }, setTitle: { $0.title = $1 }
        )
        guard merged != byAccount else { return }

        byAccount = merged
        save()
        for account in merged.keys {
            WidgetSync.syncFavorites(account: account)
        }
    }
}
