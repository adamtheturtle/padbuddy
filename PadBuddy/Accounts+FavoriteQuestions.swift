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
    /// Internal, not private: the cloud merge lives in Accounts+FavoriteQuestions+Cloud.swift
    /// (split for file length), matching the convention .swiftlint.yml documents.
    var removedAt: [UUID: [String: Date]] = [:]
    private static let key = "favoriteQuestions.v2"
    private static let legacyKey = "favoriteQuestions.v1"
    private static let tombstonesKey = "favoriteQuestions.tombstones.v1"
    /// The iCloud mirror, keyed by each account's stable sync id rather than the
    /// per-device `UUID`, under its own key (#536).
    static let cloudKey = "favoriteQuestions.cloud.v1"
    static let cloudTombstonesKey = "favoriteQuestions.tombstones.cloud.v1"
    private var cloudObserver: (any NSObjectProtocol)?

    /// Sanity caps for the persisted and mirrored favorites (#1788); mirrors
    /// `FavoritePadsStore`.
    /// Set when a star is refused because the account is at `maxEntriesPerAccount`. The
    /// caps were applied only on decode, so starring past them looked fine until the next
    /// launch truncated — with no tombstone, so the cloud merge could bring them back
    /// (#4788).
    var limitNotice: String?

    static let maxEntriesPerAccount = 500
    static let maxTitleLength = 256

    /// Bounded at capture: the full title was persisted and mirrored, then silently
    /// shortened on reload (#4788).
    static func boundedTitle(_ title: String) -> String {
        String(title.prefix(maxTitleLength))
    }

    static var limitReachedMessage: String {
        String(localized: """
        This account already has \(maxEntriesPerAccount) favorite questions. \
        Remove one before adding another.
        """)
    }

    /// Clamps a decoded entries array to the sanity caps (#1788).
    static func sanitized(_ entries: [FavoriteQuestion]) -> [FavoriteQuestion] {
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
        if let decoded = Self.decodePersisted([UUID: [FavoriteQuestion]].self, key: Self.key) {
            byAccount = decoded.mapValues(Self.sanitized)
        } else if let legacy = Self.decodePersisted([UUID: [Int]].self, key: Self.legacyKey) {
            // Carry id-only favorites saved before titles were stored into the new
            // shape with empty titles; they're backfilled from the cache by
            // `refreshTitles` as soon as the account's questions load.
            // Through `sanitized` like the v2 branch, which the legacy path skipped (#4787).
            byAccount = legacy.mapValues { ids in
                // `add` rejects a non-positive id; the migration accepted one, and it
                // became a permanent sidebar row that could never resolve (#2521).
                Self.sanitized(ids.filter { $0 > 0 }.map { FavoriteQuestion(id: $0, title: "") })
            }
            save()
            UserDefaults.standard.removeObject(forKey: Self.legacyKey)
        }
        if let decoded = Self.decodePersisted([UUID: [String: Date]].self, key: Self.tombstonesKey) {
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

    /// Whether the account has any starred questions, without allocating the id
    /// array returned by `favorites(account:)` merely to inspect its emptiness.
    func hasFavorites(account: UUID?) -> Bool {
        guard let account else { return false }

        return byAccount[account]?.isEmpty == false
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
            actionName = String(localized: "Remove Favorite from \(favoriteAccountName(account))")
        } else {
            guard entries.count < Self.maxEntriesPerAccount else {
                limitNotice = Self.limitReachedMessage
                return
            }

            entries.append(FavoriteQuestion(id: id, title: Self.boundedTitle(title),
                                            addedAt: mutationTimestamp(account: account)))
            actionName = String(localized: "Add Favorite")
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

            entries[index].title = Self.boundedTitle(title)
        } else {
            guard entries.count < Self.maxEntriesPerAccount else {
                limitNotice = Self.limitReachedMessage
                return
            }

            entries.append(FavoriteQuestion(id: id, title: Self.boundedTitle(title),
                                            addedAt: mutationTimestamp(account: account)))
        }
        byAccount[account] = entries
        save()
        WidgetSync.syncFavorites(account: account)
        registerUndo(to: before, account: account, undoManager: undoManager,
                     actionName: String(localized: "Add Favorite"))
    }

    /// Drops every starred question for an account, called when the account is
    /// removed or re-keyed so its question ids and captured titles don't linger in
    /// UserDefaults — the titles can carry candidate names, a privacy concern (#379).
    func remove(account: UUID, syncID: String? = nil) {
        if let syncID {
            removeFromCloud(syncID: syncID)
        }
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
        // Drop the saved drag position; undo's snapshot restores it (#2512).
        let order = FavoritesOrderStore.shared.snapshot(account: account)
        FavoritesOrderStore.shared.forget(FavoriteRef.question(id), account: account)
        save()
        WidgetSync.syncFavorites(account: account)
        let actionName = String(localized: "Remove Favorite from \(favoriteAccountName(account))")
        registerUndo(to: before, account: account, undoManager: undoManager,
                     actionName: actionName, order: order)
    }

    private func favoriteAccountName(_ id: UUID) -> String {
        AccountsStore.shared.accounts.first { $0.id == id }?.name ?? String(localized: "account")
    }

    func recordRemoval(of id: Int, account: UUID) {
        removedAt[account, default: [:]][String(id)] = mutationTimestamp(account: account)
    }

    private func mutationTimestamp(account: UUID, now: Date = Date()) -> Date {
        let additions = (byAccount[account] ?? []).compactMap(\.addedAt)
        let removals = Array(removedAt[account, default: [:]].values)
        return CloudTombstones.nextTimestamp(observing: additions + removals, now: now)
    }

    /// Updates stored titles from a freshly loaded question list, so a favorite's
    /// name stays current after a rename and legacy id-only favorites gain a title.
    /// Called when an account's questions cache is refreshed; a no-op when nothing
    /// actually changed, so it doesn't churn the store on every load.
    func refreshTitles(from questions: [Question], account: UUID) {
        guard let entries = byAccount[account], !entries.isEmpty else { return }

        let titles = Dictionary(
            questions.map { ($0.id, $0.displayTitle) },
            uniquingKeysWith: { first, _ in first }
        )
        let result = FavoriteQuestionRefresh.reconcile(entries, authoritativeTitles: titles)
        guard result.entries != entries else { return }

        for id in result.removedIDs {
            recordRemoval(of: id, account: account)
            FavoritesOrderStore.shared.forget(FavoriteRef.question(id), account: account)
        }
        byAccount[account] = result.entries
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
        removedAt = Self.prunedTombstones(memberships: byAccount, tombstones: removedAt)
        // Tombstones first, both encoded before either is written: a membership without
        // its tombstone is how a removed favourite returns through the cloud merge
        // (#4786).
        do {
            let data = try SharedCoders.encoder.encode(byAccount)
            let tombstones = try SharedCoders.encoder.encode(removedAt)
            UserDefaults.standard.set(tombstones, forKey: Self.tombstonesKey)
            UserDefaults.standard.set(data, forKey: Self.key)
        } catch {
            let reason = error.localizedDescription
            persistenceLogger.error("Failed to encode favorite questions: \(reason, privacy: .public)")
        }
        mirrorToCloud()
    }

    /// Retires re-added question ids and ages out deletions even when an account
    /// has no favorites left. Iterating memberships alone skipped exactly those
    /// tombstone-only accounts, so their maps could live forever (#1084).
    static func prunedTombstones(
        memberships: [UUID: [FavoriteQuestion]],
        tombstones: [UUID: [String: Date]],
        now: Date = Date()
    ) -> [UUID: [String: Date]] {
        var result: [UUID: [String: Date]] = [:]
        for account in Set(memberships.keys).union(tombstones.keys) {
            guard var accountTombstones = tombstones[account] else { continue }

            for entry in memberships[account] ?? [] {
                accountTombstones[String(entry.id)] = nil
            }
            let pruned = CloudTombstones.pruned(accountTombstones, now: now)
            if !pruned.isEmpty {
                result[account] = pruned
            }
        }
        return result
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
}
