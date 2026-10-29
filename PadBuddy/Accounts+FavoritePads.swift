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

/// A pad list's reload id: what the list's rows depend on beyond the pads
/// themselves, namely which favourites are pinned. Carrying the store's
/// revision keeps it O(1) to build, where joining every favourite id into a
/// string allocated afresh on every body pass — selection-only re-renders
/// included (#2101).
struct FavoritesReloadID: Hashable {
    /// The account whose favourites the list shows, or `nil` for a merged list
    /// spanning every account (there, a change to the account set already
    /// changes the rows' own ids, so the list reloads without help from here).
    let account: UUID?
    let revision: UInt64
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
    var byAccount: [UUID: [FavoritePad]] = [:]
    /// Dated per-account deletion tombstones, so an unfavorite converges across
    /// devices instead of being unioned back by another Mac's mirror (#738).
    var removedAt: [UUID: [String: Date]] = [:]
    private static let key = "favoritePads.v2"
    private static let tombstonesKey = "favoritePads.tombstones.v1"
    /// The iCloud mirror is keyed by each account's stable sync id (a `String`), not
    /// the per-device `UUID` the local blob uses, so it lives under its own key with
    /// its own schema (#536).
    static let cloudKey = "favoritePads.cloud.v1"
    static let cloudTombstonesKey = "favoritePads.tombstones.cloud.v1"
    /// singleton that lives for the whole process, so it's never explicitly stopped.
    /// singleton that lives for the whole process, so it is never explicitly stopped.
    private var cloudObserverTask: Task<Void, Never>?
    /// The tombstone map as last written to defaults, and as last mirrored together
    /// with the sync-id index that keyed it, so a save that did not touch the
    /// tombstones skips re-encoding and re-uploading an identical blob (#2080).
    private var writtenTombstones: [UUID: [String: Date]]?
    var mirroredTombstones: (tombstones: [UUID: [String: Date]], syncIDs: [UUID: String])?
    /// Bumped whenever the stored favourites change, so a list can tell "did the
    /// favourites change?" in O(1) (see ``FavoritesReloadID``) instead of joining
    /// every favourite id into a fresh signature string on every body pass (#2101).
    private(set) var revision: UInt64 = 0

    /// Sanity caps for the persisted and mirrored favorites (#1788): more entries
    /// than a sidebar could ever show, or titles far past any real pad name, mean
    /// corrupt or injected data - decoding them verbatim would burn launch
    /// memory, sidebar work, and cloud writes.
    /// Set when a star is refused because the account is at `maxEntriesPerAccount`. As for
    /// starred questions, the caps were applied only on decode (#4788).
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
        This account already has \(maxEntriesPerAccount) favorite pads. \
        Remove one before adding another.
        """)
    }

    /// Clamps a decoded entries array to the sanity caps (#1788).
    static func sanitized(_ entries: [FavoritePad]) -> [FavoritePad] {
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
        if let data = UserDefaults.standard.data(forKey: Self.key) {
            do {
                let decoded: [UUID: [FavoritePad]] = try FavoritePadLocalRestoration.decode(
                    data,
                    context: "favorite pad membership"
                )
                byAccount = decoded.mapValues(Self.sanitized)
            } catch {
                persistenceLogger.error("\(error.localizedDescription, privacy: .public)")
            }
        }
        if let data = UserDefaults.standard.data(forKey: Self.tombstonesKey) {
            do {
                removedAt = try FavoritePadLocalRestoration.decode(
                    data,
                    context: "favorite pad removal history"
                )
            } catch {
                persistenceLogger.error("\(error.localizedDescription, privacy: .public)")
            }
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
            let boundedTitle = Self.boundedTitle(title)
            guard entries[index].title != boundedTitle else { return }

            entries[index].title = boundedTitle
        } else {
            guard entries.count < Self.maxEntriesPerAccount else {
                limitNotice = Self.limitReachedMessage
                return
            }

            entries.append(FavoritePad(id: padID, title: Self.boundedTitle(title),
                                       addedAt: mutationTimestamp(account: account)))
        }
        byAccount[account] = entries
        save(account: account)
        registerUndo(to: before, account: account, undoManager: undoManager,
                     actionName: String(localized: "Add Favorite"))
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
            actionName = String(localized: "Remove Favorite")
        } else {
            guard entries.count < Self.maxEntriesPerAccount else {
                limitNotice = Self.limitReachedMessage
                return
            }

            entries.append(FavoritePad(id: id, title: Self.boundedTitle(title),
                                       addedAt: mutationTimestamp(account: account)))
            actionName = String(localized: "Add Favorite")
        }
        byAccount[account] = entries
        save(account: account)
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
        save(account: account)
        registerUndo(to: before, account: account, undoManager: undoManager,
                     actionName: String(localized: "Remove Favorite"), order: order)
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
            guard let title = titles[entries[index].id] else { continue }

            let boundedTitle = Self.boundedTitle(title)
            guard boundedTitle != entries[index].title else { continue }

            entries[index].title = boundedTitle
            changed = true
        }
        guard changed else { return }

        byAccount[account] = entries
        save(account: account)
    }

    /// Drops every favorite for an account, called when the account is removed or
    /// re-keyed so its pinned pad ids don't linger in UserDefaults (#379).
    func remove(account: UUID, syncID: String? = nil) {
        AccountUndoLifetime.invalidate(account)
        if let syncID {
            removeFromCloud(syncID: syncID)
        }
        guard byAccount[account] != nil || removedAt[account] != nil else { return }

        byAccount[account] = nil
        removedAt[account] = nil
        save(account: account)
    }

    private func removeFromCloud(syncID: String) {
        guard CloudSyncStore.shared.isAvailable else { return }

        removeCloudAccount(syncID, key: Self.cloudKey, value: [FavoritePad].self)
        removeCloudAccount(syncID, key: Self.cloudTombstonesKey, value: [String: Date].self)
    }

    private func removeCloudAccount<Value: Codable>(_ syncID: String, key: String, value _: Value.Type) {
        guard let data = CloudSyncStore.shared.data(forKey: key),
              let cloud = try? SharedCoders.decoder.decode([String: Value].self, from: data),
              let updatedCloud = CloudSyncMerge.removingAccount(syncID, from: cloud),
              let updated = try? SharedCoders.encoder.encode(updatedCloud)
        else { return }

        CloudSyncStore.shared.mirror(updated, forKey: key)
    }

    /// Records a dated deletion tombstone so the removal propagates through the
    /// additive iCloud merge instead of being unioned back (#738).
    func recordRemoval(of id: String, account: UUID) {
        removedAt[account, default: [:]][id] = mutationTimestamp(account: account)
    }

    func mutationTimestamp(account: UUID, now: Date = Date()) -> Date {
        let additions = (byAccount[account] ?? []).compactMap(\.addedAt)
        let removals = Array(removedAt[account, default: [:]].values)
        return CloudTombstones.nextTimestamp(observing: additions + removals, now: now)
    }

    /// Persists after a mutation. `account` is the account that changed, or `nil`
    /// when every account may have (a cloud merge).
    func save(account: UUID?) {
        // Every mutation lands here, so this is the one place the revision has to
        // move for observers to see a favourites change (#2101).
        revision &+= 1
        // A present id retires its tombstone (re-added locally, incl. via undo),
        // and old tombstones age out so the map stays bounded. Only the mutated
        // account is walked: retiring every account's tombstones on each add,
        // toggle, move and title refresh was work proportional to the whole
        // multi-account structure for a change that could not have touched the
        // rest of it (#2080). Tombstones only ever grow through removals, and a
        // removal always saves its own account, so the per-account cap still holds.
        let touched = account.map { [$0] } ?? Array(byAccount.keys)
        for account in touched {
            guard var tombstones = removedAt[account] else { continue }

            for entry in byAccount[account] ?? [] {
                tombstones[entry.id] = nil
            }
            removedAt[account] = CloudTombstones.pruned(tombstones)
        }
        // Both blobs encoded before either is written, and the tombstones written first.
        // Writing them one at a time could leave a membership without its tombstone if the
        // second encode threw, and a record without its tombstone is exactly how a removed
        // favourite comes back through the cloud merge. Tombstones-without-records is the
        // harmless direction — the ordering `PadOpenedStore.save()` spells out and this
        // store had backwards (#4786).
        do {
            let data = try SharedCoders.encoder.encode(byAccount)
            // Most mutations leave the tombstones alone, and defaults already hold
            // what was last written, so re-encoding an identical blob every time was
            // pure churn (#2080).
            if writtenTombstones != removedAt {
                let tombstones = try SharedCoders.encoder.encode(removedAt)
                UserDefaults.standard.set(tombstones, forKey: Self.tombstonesKey)
                writtenTombstones = removedAt
            }
            UserDefaults.standard.set(data, forKey: Self.key)
        } catch {
            let reason = error.localizedDescription
            persistenceLogger.error("Failed to encode favorite pads: \(reason, privacy: .public)")
        }
        mirrorToCloud()
    }
}
