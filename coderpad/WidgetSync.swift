//
//  WidgetSync.swift
//  coderpad
//
//  Bridges the app's pad data to the Recent Pads widget. The widget lives in its
//  own sandbox, so it can't read the app's cache directly; instead the app mirrors
//  a small slice of the current account's recent pads into the shared App Group
//  container (see `WidgetSharedStore`) and asks WidgetKit to refresh.
//

import Foundation
import WidgetKit

enum WidgetSync {
    /// How many pads the widget ever needs, even at its largest size.
    private static let maxPads = 8

    /// Serializes the widget mirror's JSON encode + atomic disk writes off the main
    /// actor, so a cache `set` (which fires on every list reload and the 5-minute
    /// background refresh) doesn't block the UI on file I/O (#373). Serial so writes
    /// to the same shared files stay ordered.
    private static let writeQueue = DispatchQueue(label: "com.coderpad.widget-sync", qos: .utility)

    /// Accounts torn down this session, guarded by `writeQueue` (every access runs on
    /// it). A refresh enqueued before a removal must not recreate the removed
    /// account's snapshot when it runs after it (#724); re-adding the account clears
    /// its tombstone via `syncAccounts`.
    private nonisolated(unsafe) static var removedAccounts: Set<UUID> = []

    /// Mirrors one account's most recently updated pads into the shared container,
    /// keyed by account id so a configured widget can pin it. When `isCurrent`, it
    /// also rewrites the default snapshot an unconfigured widget reads. Cheap and
    /// idempotent, so it's safe to call on every cache update; a no-op when the App
    /// Group container is unavailable.
    ///
    /// Deliberately takes no dependency on `AccountsStore.shared`: it runs from
    /// `AccountsStore`'s own property observers, which the Observation macro also
    /// fires during the store's `init` — re-entering the singleton there would
    /// deadlock its one-time initializer.
    static func refresh(pads: [Pad], account accountID: UUID, isCurrent: Bool) {
        // Build the small snapshot slice on the caller (cheap: a sort + prefix of
        // `maxPads`), then hand the encode + atomic writes to a background queue so
        // the main actor isn't blocked on disk I/O (#373).
        let snapshots = recentSnapshots(from: pads)
        writeQueue.async {
            guard !removedAccounts.contains(accountID) else { return }

            WidgetSharedStore.save(snapshots, account: accountID.uuidString)
            if isCurrent {
                WidgetSharedStore.save(snapshots)
            }
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Clears the default snapshot (read when no account is pinned) and reloads, for
    /// when there is no current account. Ordered through the same serial queue as
    /// the refresh writes, so a refresh enqueued earlier can't run after this clear
    /// and repopulate the snapshot it just emptied (#753).
    static func clearCurrent() {
        writeQueue.async {
            WidgetSharedStore.save([])
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Mirrors the account list (id + name) into the shared container so the widget's
    /// configuration picker can list accounts from inside the widget process. Takes
    /// the accounts explicitly rather than reading `AccountsStore.shared`, so it's
    /// safe to call from the `accounts` observer during the store's own init.
    static func syncAccounts(_ accounts: [Account]) {
        // An account that exists (again) is no longer torn down; drop its tombstone
        // so its snapshots refresh normally after a remove-and-re-add.
        let present = Set(accounts.map(\.id))
        writeQueue.async { removedAccounts.subtract(present) }
        WidgetSharedStore.saveAccounts(accounts.map {
            WidgetAccount(id: $0.id.uuidString, name: $0.name)
        })
    }

    /// Mirrors an account's favourite questions (id + title) into the shared
    /// container so the New Pad button's configuration picker can list them. Titles
    /// come from the favourites store's *stored* titles (#325), which are persisted
    /// and available even before the account's questions have loaded — so the picker
    /// populates on a cold launch; a fresher cache title is preferred when present,
    /// and an as-yet-untitled legacy favourite falls back to "#id". Safe to call from
    /// the favourites/questions stores, which are never mutated during `AccountsStore`'s
    /// init.
    static func syncFavorites(account accountID: UUID) {
        let favorites = FavoriteQuestionsStore.shared.titledFavorites(account: accountID)
        guard !favorites.isEmpty else {
            WidgetSharedStore.saveFavorites([], account: accountID.uuidString)
            return
        }

        let cacheTitles = Dictionary(
            QuestionsCacheStore.shared.get(accountID).map { ($0.id, $0.displayTitle) },
            uniquingKeysWith: { first, _ in first }
        )
        let widgetFavorites = favorites.map { favorite in
            let title = cacheTitles[favorite.id] ?? (favorite.title.isEmpty ? "#\(favorite.id)" : favorite.title)
            return WidgetQuestion(id: favorite.id, title: title)
        }
        WidgetSharedStore.saveFavorites(widgetFavorites, account: accountID.uuidString)
    }

    /// Mirrors every account's favourite questions at once, so the widget's New Pad
    /// question picker is populated on a fresh launch — before any account's Questions
    /// section has been opened, which is what otherwise triggers the per-account sync.
    /// Called once at launch.
    static func syncAllFavorites(_ accounts: [Account]) {
        for account in accounts {
            syncFavorites(account: account.id)
        }
    }

    /// Drops a removed account's per-account snapshot and reloads. The account index
    /// is refreshed separately when the accounts list itself changes. Ordered through
    /// the serial write queue AND tombstoned, so a refresh enqueued before the
    /// removal (whose closure captured the account's pads) can't write the snapshot
    /// back after teardown (#724).
    static func removeAccount(_ accountID: UUID) {
        writeQueue.async {
            removedAccounts.insert(accountID)
            WidgetSharedStore.deletePads(account: accountID.uuidString)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Drops a re-keyed account's snapshot (its pads belong to the old backend)
    /// WITHOUT tombstoning it: the account persists across a re-key, and the
    /// tombstone is never cleared for a still-present account, so it would block
    /// every future refresh and leave the widget blank indefinitely (#1022). Also
    /// clears any tombstone left from the remove-vs-rekey ordering, and the
    /// default snapshot when the re-keyed account is the current one.
    static func clearAccount(_ accountID: UUID, isCurrent: Bool) {
        writeQueue.async {
            removedAccounts.remove(accountID)
            WidgetSharedStore.deletePads(account: accountID.uuidString)
            if isCurrent {
                WidgetSharedStore.save([])
            }
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private static func recentSnapshots(from pads: [Pad]) -> [WidgetPadSnapshot] {
        pads
            .sorted { lhs, rhs in
                (lhs.updatedAt ?? lhs.createdAt ?? .distantPast)
                    > (rhs.updatedAt ?? rhs.createdAt ?? .distantPast)
            }
            .prefix(maxPads)
            .map { pad in
                WidgetPadSnapshot(
                    id: pad.id,
                    title: pad.title.isEmpty ? "Untitled pad" : pad.title,
                    subtitle: pad.ownerEmail,
                    language: pad.language,
                    updatedAt: pad.updatedAt ?? pad.createdAt
                )
            }
    }
}
