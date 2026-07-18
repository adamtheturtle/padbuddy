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
    /// When this favorite was (re-)starred, so a deletion tombstone from another
    /// device can be ordered against it (#738). Optional so entries persisted
    /// before it existed still decode; they count as arbitrarily old.
    var addedAt: Date?
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
    /// Dated per-account deletion tombstones (keyed by the stringified question
    /// id), so an unstar converges across devices instead of being unioned back
    /// by another Mac's mirror (#738).
    private var removedAt: [UUID: [String: Date]] = [:]
    private static let key = "favoriteQuestions.v2"
    private static let legacyKey = "favoriteQuestions.v1"
    private static let tombstonesKey = "favoriteQuestions.tombstones.v1"
    /// The iCloud mirror, keyed by each account's stable sync id rather than the
    /// per-device `UUID`, under its own key (#536).
    private static let cloudKey = "favoriteQuestions.cloud.v1"
    private static let cloudTombstonesKey = "favoriteQuestions.tombstones.cloud.v1"
    private var cloudObserver: (any NSObjectProtocol)?

    /// Sanity caps for the persisted and mirrored favorites (#1788); mirrors
    /// `FavoritePadsStore`.
    static let maxEntriesPerAccount = 500
    static let maxTitleLength = 256

    /// Clamps a decoded entries array to the sanity caps (#1788).
    private static func sanitized(_ entries: [FavoriteQuestion]) -> [FavoriteQuestion] {
        entries.prefix(maxEntriesPerAccount).map { entry in
            var entry = entry
            if entry.title.count > maxTitleLength {
                entry.title = String(entry.title.prefix(maxTitleLength))
            }
            return entry
        }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([UUID: [FavoriteQuestion]].self, from: data) {
            byAccount = decoded.mapValues(Self.sanitized)
        } else if let data = UserDefaults.standard.data(forKey: Self.legacyKey),
                  let legacy = try? JSONDecoder().decode([UUID: [Int]].self, from: data) {
            // Carry id-only favorites saved before titles were stored into the new
            // shape with empty titles; they're backfilled from the cache by
            // `refreshTitles` as soon as the account's questions load.
            byAccount = legacy.mapValues { ids in ids.map { FavoriteQuestion(id: $0, title: "") } }
            save()
            UserDefaults.standard.removeObject(forKey: Self.legacyKey)
        }
        if let data = UserDefaults.standard.data(forKey: Self.tombstonesKey),
           let decoded = try? JSONDecoder().decode([UUID: [String: Date]].self, from: data) {
            removedAt = decoded
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
            recordRemoval(of: id, account: account)
            actionName = "Remove Favorite"
        } else {
            entries.append(FavoriteQuestion(id: id, title: title, addedAt: Date()))
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
        entries.append(FavoriteQuestion(id: id, title: title, addedAt: Date()))
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
        guard byAccount[account] != nil || removedAt[account] != nil else { return }

        byAccount[account] = nil
        removedAt[account] = nil
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
        recordRemoval(of: id, account: account)
        save()
        WidgetSync.syncFavorites(account: account)
        registerUndo(to: before, account: account, undoManager: undoManager, actionName: "Remove Favorite")
    }

    /// Records a dated deletion tombstone so the removal propagates through the
    /// additive iCloud merge instead of being unioned back (#738).
    private func recordRemoval(of id: Int, account: UUID) {
        removedAt[account, default: [:]][String(id)] = Date()
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
            // Trimmed, not just non-empty: a whitespace-only question name must
            // not replace a usable stored label with a blank row (#1787).
            guard let title = titles[entries[index].id],
                  !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  title != entries[index].title else { continue }

            entries[index].title = title
            changed = true
        }
        guard changed else { return }

        byAccount[account] = entries
        save()
        WidgetSync.syncFavorites(account: account)
    }

    private func save() {
        // A present id retires its tombstone (re-starred locally, incl. via undo),
        // and old tombstones age out so the map stays bounded.
        for (account, entries) in byAccount {
            guard var tombstones = removedAt[account] else { continue }

            for entry in entries {
                tombstones[String(entry.id)] = nil
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
            persistenceLogger.error("Failed to encode favorite questions: \(reason, privacy: .public)")
        }
        mirrorToCloud()
    }

    private func restore(_ entries: [FavoriteQuestion], account: UUID, undoManager: UndoManager?, actionName: String) {
        let before = byAccount[account] ?? []
        // Anything the restore drops relative to the current list is a removal to
        // propagate; anything it (re-)introduces is stamped as freshly added so it
        // beats any remote tombstone (#738).
        let restoredIDs = Set(entries.map(\.id))
        for entry in before where !restoredIDs.contains(entry.id) {
            recordRemoval(of: entry.id, account: account)
        }
        byAccount[account] = entries.map { entry in
            var entry = entry
            entry.addedAt = Date()
            return entry
        }
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

    /// Pushes the current favourites (and their deletion tombstones, #738) up to
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
        if let data = try? JSONEncoder().encode(CloudSyncMerge.toCloud(removedAt, syncID: syncID)) {
            CloudSyncStore.shared.mirror(data, forKey: Self.cloudTombstonesKey)
        }
    }

    /// Pulls the iCloud favourites and merges them into the local set, unioning by
    /// question id so a title backfilled on only one device never forks an entry,
    /// then resolves deletion tombstones so an unstar made on another Mac converges
    /// here instead of being unioned back (#738), and persists. Called once accounts
    /// have loaded and on every external iCloud change. No-op when iCloud is
    /// unavailable (#536).
    func syncFromCloud() {
        guard let data = CloudSyncStore.shared.data(forKey: Self.cloudKey),
              let decoded = try? JSONDecoder().decode([String: [FavoriteQuestion]].self, from: data) else { return }

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
