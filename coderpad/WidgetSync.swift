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
            WidgetSharedStore.save(snapshots, account: accountID.uuidString)
            if isCurrent {
                WidgetSharedStore.save(snapshots)
            }
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Clears the default snapshot (read when no account is pinned) and reloads, for
    /// when there is no current account.
    static func clearCurrent() {
        WidgetSharedStore.save([])
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Mirrors the account list (id + name) into the shared container so the widget's
    /// configuration picker can list accounts from inside the widget process. Takes
    /// the accounts explicitly rather than reading `AccountsStore.shared`, so it's
    /// safe to call from the `accounts` observer during the store's own init.
    static func syncAccounts(_ accounts: [Account]) {
        WidgetSharedStore.saveAccounts(accounts.map {
            WidgetAccount(id: $0.id.uuidString, name: $0.name)
        })
    }

    /// Mirrors an account's favourite questions (id + title) into the shared
    /// container so the New Pad button's configuration picker can list them. Titles
    /// are resolved from whatever questions are cached for the account; ids without a
    /// cached title fall back to "#id". Safe to call from the favourites/questions
    /// stores, which are never mutated during `AccountsStore`'s init.
    static func syncFavorites(account accountID: UUID) {
        let favoriteIDs = FavoriteQuestionsStore.shared.favorites(account: accountID)
        guard !favoriteIDs.isEmpty else {
            WidgetSharedStore.saveFavorites([], account: accountID.uuidString)
            return
        }

        let titles = Dictionary(
            QuestionsCacheStore.shared.get(accountID).map { ($0.id, $0.displayTitle) },
            uniquingKeysWith: { first, _ in first }
        )
        let favorites = favoriteIDs.map { WidgetQuestion(id: $0, title: titles[$0] ?? "#\($0)") }
        WidgetSharedStore.saveFavorites(favorites, account: accountID.uuidString)
    }

    /// Drops a removed account's per-account snapshot and reloads. The account index
    /// is refreshed separately when the accounts list itself changes.
    static func removeAccount(_ accountID: UUID) {
        WidgetSharedStore.deletePads(account: accountID.uuidString)
        WidgetCenter.shared.reloadAllTimelines()
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
