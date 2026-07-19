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
    // A few members below are internal rather than private because the undo/restore
    // half of this store lives in Accounts+FavoriteQuestions+Undo.swift, split out to
    // keep both files within the file-length limit.
    static let shared = FavoriteQuestionsStore()
    var byAccount: [UUID: [FavoriteQuestion]] = [:]
    /// Bumped by `save()` — the funnel every membership change goes through — so
    /// callers can tell "the favorites may have changed" from an Int compare.
    /// The list views memoize their filtered rows and list-reload ids against the
    /// favorites, and rebuilding a Set (or a joined id string) per account just to
    /// build those keys cost O(favorites) allocations on every body pass
    /// (#2082, #2083, #2084, #2085). Observable, so reading only this still
    /// invalidates a view when a favorite is toggled.
    private(set) var revision = 0
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
        // De-duplicate by id first. Decoded data was trusted as-is, so a blob that
        // had picked up a repeat — from a bad merge, a restore, or an older build —
        // produced two sidebar rows for one question, made `toggle` remove only one of
        // them, and left tombstone resolution ambiguous (#2528). First occurrence
        // wins, which keeps the pinned order the user arranged.
        var seen = Set<Int>()
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
           let decoded = try? SharedCoders.decoder.decode([UUID: [FavoriteQuestion]].self, from: data) {
            byAccount = decoded.mapValues(Self.sanitized)
        } else if let data = UserDefaults.standard.data(forKey: Self.legacyKey),
                  let legacy = try? SharedCoders.decoder.decode([UUID: [Int]].self, from: data) {
            // Carry id-only favorites saved before titles were stored into the new
            // shape with empty titles; they're backfilled from the cache by
            // `refreshTitles` as soon as the account's questions load.
            byAccount = legacy.mapValues { ids in ids.map { FavoriteQuestion(id: $0, title: "") } }
            save()
            UserDefaults.standard.removeObject(forKey: Self.legacyKey)
        }
        if let data = UserDefaults.standard.data(forKey: Self.tombstonesKey),
           let decoded = try? SharedCoders.decoder.decode([UUID: [String: Date]].self, from: data) {
            removedAt = decoded
        }
        cloudObserver = NotificationCenter.default.addObserver(
            forName: CloudSyncStore.didChangeExternally, object: nil, queue: .main
        ) { note in
            let key = note.userInfo?["key"] as? String
            // Delivered on the main queue, so we're already on the main actor.
            MainActor.assumeIsolated {
                // The tombstone blob changes independently of the membership blob: a
                // remote unfavourite writes only the former. Watching just the
                // membership key left that removal unreconciled — the favourite stayed
                // in the sidebar until some unrelated change happened to rewrite the
                // membership blob as well (#2526).
                guard key == Self.cloudKey || key == Self.cloudTombstonesKey else { return }

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
        // Captured before the branch so an unfavourite can hand it to its undo; a
        // favourite that isn't removed leaves the order untouched, so it costs nothing.
        let order = FavoritesOrderStore.shared.snapshot(account: account)
        if let index = entries.firstIndex(where: { $0.id == id }) {
            entries.remove(at: index)
            recordRemoval(of: id, account: account)
            // The saved drag position goes with the favourite (#2512).
            FavoritesOrderStore.shared.forget(FavoriteRef.question(id), account: account)
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
        registerUndo(to: before, account: account, undoManager: undoManager,
                     actionName: actionName, order: order)
    }

    /// Favorites the question if it isn't already, preserving order. Used by the
    /// sidebar drop target, where a drop should only ever add a favorite (never
    /// remove one), so a no-op when it's already starred.
    func add(_ id: Int, title: String, account: UUID, undoManager: UndoManager? = nil) {
        // A drop payload carries an arbitrary integer. CoderPad question ids are
        // positive, so a zero or negative one is a shortcut that can never resolve to
        // a server question — it would just sit in the sidebar forever (#2521).
        guard id > 0 else { return }

        var entries = byAccount[account] ?? []
        let before = entries
        if let index = entries.firstIndex(where: { $0.id == id }) {
            // Already pinned. Returning here meant dropping a renamed question onto
            // Favorites couldn't correct its captured title, which stayed stale until
            // an unrelated questions refresh happened along (#2523). Take the newer
            // title and leave `addedAt` alone — this is not a new pin.
            guard entries[index].title != title else { return }

            entries[index].title = title
        } else {
            entries.append(FavoriteQuestion(id: id, title: title, addedAt: Date()))
        }
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
        // Drop the saved drag position too. Reconciliation hid the stale ref, but it
        // stayed in defaults and iCloud forever and silently restored the old position
        // if this was ever favourited again (#2512). The snapshot lets undo put it back
        // where it was rather than appending it.
        let order = FavoritesOrderStore.shared.snapshot(account: account)
        FavoritesOrderStore.shared.forget(FavoriteRef.question(id), account: account)
        save()
        WidgetSync.syncFavorites(account: account)
        registerUndo(to: before, account: account, undoManager: undoManager,
                     actionName: "Remove Favorite", order: order)
    }

    /// Records a dated deletion tombstone so the removal propagates through the
    /// additive iCloud merge instead of being unioned back (#738).
    func recordRemoval(of id: Int, account: UUID) {
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
            // A cleared title propagates. Blank titles used to be skipped so a
            // usable stored label wasn't replaced by a blank row (#1787), but the
            // sidebar now treats a blank stored title as absent and falls back to the
            // live cache title and then "Question #id" (#1680, #1681) — so the row
            // stays readable either way, and keeping the old text meant showing a name
            // the server no longer has (#2524).
            guard let title = titles[entries[index].id], title != entries[index].title else { continue }

            entries[index].title = title
            changed = true
        }
        guard changed else { return }

        byAccount[account] = entries
        save()
        WidgetSync.syncFavorites(account: account)
    }

    func save() {
        // Every membership change lands here, so this is the one place the
        // revision has to move. Bumping on a save that changed nothing only costs
        // an extra memo rebuild, whereas missing one would show stale rows.
        revision &+= 1
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
            let data = try SharedCoders.encoder.encode(byAccount)
            UserDefaults.standard.set(data, forKey: Self.key)
            let tombstones = try SharedCoders.encoder.encode(removedAt)
            UserDefaults.standard.set(tombstones, forKey: Self.tombstonesKey)
        } catch {
            let reason = error.localizedDescription
            persistenceLogger.error("Failed to encode favorite questions: \(reason, privacy: .public)")
        }
        mirrorToCloud()
    }

    /// Pushes the current favourites (and their deletion tombstones, #738) up to
    /// iCloud, keyed by each account's stable sync id. No-op when iCloud is
    /// unavailable (#536).
    private func mirrorToCloud() {
        guard CloudSyncStore.shared.isAvailable else { return }

        // Indexed once rather than scanned per account (#2439).
        let syncIDs = AccountsStore.shared.syncIDsByAccountID
        let syncID: (UUID) -> String? = { syncIDs[$0] }
        if let data = try? SharedCoders.encoder.encode(CloudSyncMerge.toCloud(byAccount, syncID: syncID)) {
            CloudSyncStore.shared.mirror(data, forKey: Self.cloudKey)
        }
        if let data = try? SharedCoders.encoder.encode(CloudSyncMerge.toCloud(removedAt, syncID: syncID)) {
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
        guard let data = CloudSyncStore.shared.data(forKey: Self.cloudKey) else { return }
        guard let decoded = try? SharedCoders.decoder
            .decode([String: [FavoriteQuestion]].self, from: data) else { return }

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
           let cloudTombstones = try? SharedCoders.decoder.decode([String: [String: Date]].self, from: data) {
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
