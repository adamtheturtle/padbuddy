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

    /// Which account currently owns the default snapshot, guarded by `writeQueue`
    /// (every access runs on it).
    ///
    /// The default snapshot is what an unconfigured widget shows, and callers used
    /// to decide whether to write it by capturing an `isCurrent` flag at call time.
    /// A refresh queued while account A was current then ran after a switch to B —
    /// or after a sign-out cleared the snapshot — and rewrote it with A's pads
    /// (#2583, #2584). Deciding on the queue, against the account that is current
    /// *when the write actually happens*, removes the window entirely.
    private nonisolated(unsafe) static var defaultSnapshotAccount: UUID?

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
            // `isCurrent` can also *make* this account the default's owner: it is how
            // an account switch repaints the unconfigured widget. Anything else only
            // writes the default while this account still owns it.
            if isCurrent { defaultSnapshotAccount = accountID }
            if defaultSnapshotAccount == accountID {
                WidgetSharedStore.save(snapshots)
            }
            scheduleReload()
        }
    }

    /// Clears the default snapshot (read when no account is pinned) and reloads, for
    /// when there is no current account. Ordered through the same serial queue as
    /// the refresh writes, so a refresh enqueued earlier can't run after this clear
    /// and repopulate the snapshot it just emptied (#753).
    static func clearCurrent() {
        writeQueue.async {
            // Disown the default snapshot as well as emptying it, so a refresh that
            // was already queued for the signed-out account can't refill it (#2584).
            defaultSnapshotAccount = nil
            WidgetSharedStore.save([])
            scheduleReload()
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
        let index = accounts.map { WidgetAccount(id: $0.id.uuidString, name: $0.name) }
        // On the same serial queue as the snapshot writes. Writing the index
        // directly let it interleave with a removal or re-key, so the widget's
        // configuration picker could momentarily list an account whose snapshot had
        // already been deleted, or miss one whose snapshot had not been written yet
        // (#2586).
        let liveIDs = Set(accounts.map(\.id.uuidString))
        writeQueue.async {
            removedAccounts.subtract(present)
            WidgetSharedStore.saveAccounts(index)
            // Piggyback the container sweep on the account sync: it runs at launch
            // and whenever the account list changes, which is exactly when orphaned
            // per-account files become identifiable, and it costs one directory
            // listing. Ordered with the writes so it can't race a snapshot being
            // written for an account it is about to judge (#2589, #2592, #2603).
            WidgetSharedStore.sweepStaleFiles(liveAccountIDs: liveIDs)
        }
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
        // `cached`, not `get`: this runs for every account at launch (see
        // `syncAllFavorites`), and `get` falls back to a synchronous whole-file read
        // and JSON decode on the main actor for any account not yet warmed (#2448).
        // The cache is only consulted for a fresher title than the favourite already
        // stores, so a cold account simply keeps the stored one until its questions
        // load and the per-account sync runs again.
        let cacheTitles = titles(forFavorites: Set(favorites.map(\.id)),
                                 in: QuestionsCacheStore.shared.cached(accountID))
        let widgetFavorites = favorites.map { favorite in
            let title = cacheTitles[favorite.id] ?? (favorite.title.isEmpty ? "#\(favorite.id)" : favorite.title)
            return WidgetQuestion(id: favorite.id, title: title)
        }
        // Through the serial queue like the pad writes. Writing directly let two
        // concurrent syncs land out of order — an older title snapshot overwriting a
        // newer one, leaving the widget stale until the next mutation (#2602) — and
        // let a favourites write race account teardown, so a removed account's
        // favourites could reappear after their file had been deleted (#2585). The
        // tombstone check is the same one the pad writes use.
        writeQueue.async {
            guard !removedAccounts.contains(accountID) else { return }

            WidgetSharedStore.saveFavorites(widgetFavorites, account: accountID.uuidString)
        }
    }

    /// Cached titles for just these question ids. The cache holds the account's whole
    /// question list, and building a dictionary of all of it to title a handful of
    /// favourites allocated an entry per question on every favourites or questions
    /// change (#2139) — so it is scanned once against the wanted ids instead. The
    /// first entry for an id wins, matching the uniquing the dictionary used to do.
    static func titles(forFavorites favoriteIDs: Set<Int>, in questions: [Question]) -> [Int: String] {
        guard !favoriteIDs.isEmpty else { return [:] }

        var titles: [Int: String] = [:]
        titles.reserveCapacity(favoriteIDs.count)
        for question in questions where favoriteIDs.contains(question.id) && titles[question.id] == nil {
            titles[question.id] = question.displayTitle
            // Every favourite is titled; the rest of the cache can't change the result.
            if titles.count == favoriteIDs.count { break }
        }
        return titles
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

    /// Drops a removed account's widget presence entirely: its per-account snapshot
    /// and favourites, its entry in the configuration index, and the default snapshot
    /// if this account was the one supplying it.
    ///
    /// Ordered through the serial write queue AND tombstoned, so a refresh enqueued
    /// before the removal (whose closure captured the account's pads) can't write the
    /// snapshot back after teardown (#724).
    ///
    /// `remainingAccounts` is passed in rather than read from `AccountsStore.shared`,
    /// matching `syncAccounts` — this runs from the store's own observers.
    static func removeAccount(_ accountID: UUID, remainingAccounts: [Account], wasCurrent: Bool) {
        let index = remainingAccounts.map { WidgetAccount(id: $0.id.uuidString, name: $0.name) }
        writeQueue.async {
            removedAccounts.insert(accountID)
            WidgetSharedStore.deletePads(account: accountID.uuidString)
            // The index was left to whoever synced the accounts list next, so until
            // that happened the widget's configuration picker still offered an
            // account whose data had already been deleted (#2588). Rewrite it here,
            // in the same ordered section as the deletion.
            WidgetSharedStore.saveAccounts(index)
            // An unconfigured widget reads the default snapshot. If this account was
            // the one that filled it, its pads stayed on screen after the account was
            // gone (#2587).
            if wasCurrent {
                WidgetSharedStore.save([])
            }
            scheduleReload()
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
            scheduleReload()
        }
    }

    /// Whether a reload happened recently enough that another must wait, and
    /// whether a write arrived during that wait. Both guarded by `writeQueue`.
    private nonisolated(unsafe) static var reloadCoolingDown = false
    private nonisolated(unsafe) static var reloadPending = false

    /// The shortest gap between timeline reloads.
    private static let reloadCoalescingWindow: DispatchTimeInterval = .milliseconds(500)

    /// Asks WidgetKit to reload, at most once per `reloadCoalescingWindow`.
    ///
    /// Every write path called `reloadAllTimelines()` directly, and the writes are
    /// not rare: an incremental list load fires one per page, and the five-minute
    /// background refresh fires one per account. WidgetKit budgets reloads, so a
    /// burst both wastes energy and can push real updates past the throttle (#2599).
    ///
    /// Leading *and* trailing: the first reload of a burst goes out immediately, so
    /// the common single-write case is not delayed, and writes arriving during the
    /// window are folded into exactly one more reload when it closes. Dropping them
    /// instead would leave the widget showing the first write of a burst until some
    /// unrelated later write happened to come along.
    private static func scheduleReload() {
        guard !reloadCoolingDown else {
            reloadPending = true
            return
        }

        reloadCoolingDown = true
        WidgetCenter.shared.reloadAllTimelines()
        writeQueue.asyncAfter(deadline: .now() + reloadCoalescingWindow) {
            reloadCoolingDown = false
            guard reloadPending else { return }

            reloadPending = false
            scheduleReload()
        }
    }

    private static func recentSnapshots(from pads: [Pad]) -> [WidgetPadSnapshot] {
        // De-duplicate before sorting. The same pad routinely arrives in both the
        // cache seed and a fresh API page, and duplicate snapshot ids meant
        // duplicate widget rows pointing at one pad (#2597). First occurrence wins.
        var seen = Set<String>()
        let unique = pads.filter { seen.insert($0.id).inserted }
        return unique
            .sorted { lhs, rhs in
                let lhsDate = lhs.updatedAt ?? lhs.createdAt ?? .distantPast
                let rhsDate = rhs.updatedAt ?? rhs.createdAt ?? .distantPast
                // Ties break on id so the order is total. Pads sharing a timestamp —
                // or both missing one — otherwise ordered arbitrarily, so the same
                // cache could produce different rows each build, jittering the
                // widget and forcing needless timeline reloads (#2596).
                if lhsDate != rhsDate { return lhsDate > rhsDate }

                return lhs.id < rhs.id
            }
            .prefix(maxPads)
            .map { pad in
                // Trim before the empty check: a whitespace-only title rendered as a
                // blank row instead of falling back to the placeholder (#2598).
                let title = pad.title.trimmingCharacters(in: .whitespacesAndNewlines)
                return WidgetPadSnapshot(
                    id: pad.id,
                    title: title.isEmpty ? "Untitled pad" : title,
                    // Deliberately empty. This used to carry the pad's owner email,
                    // which put an identifying address into a container any process
                    // holding the App Group entitlement can read, for a caption that
                    // says little on a widget of your own recent pads — the title,
                    // language badge, and time already carry the useful signal
                    // (#2601). The field stays in the contract so snapshots written
                    // by older builds still decode; the widget hides an empty one.
                    subtitle: "",
                    language: pad.language,
                    updatedAt: pad.updatedAt ?? pad.createdAt
                )
            }
    }
}
