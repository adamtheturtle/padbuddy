//
//  Accounts+Monitors.swift
//  coderpad
//
//  Observable monitors for account key health and pad activity.
//

import AsyncAlgorithms
import BuddyAppKit
import Foundation

/// Re-checks the current account's key on a timer so a key revoked mid-session surfaces
/// the unauthorized banner without needing a section switch. A thin app-specific wrapper
/// around buddy-kit's generic ``BuddyAppKit/AccountHealthMonitor`` that folds in
/// PadBuddy's account-eligibility rules and its `quota()` liveness probe, and keeps the
/// `shared` singleton and `checkCurrentAccount()` name the app's call sites use.
@MainActor
@Observable
final class AccountHealthMonitor {
    static let shared = AccountHealthMonitor()

    private let monitor: BuddyAppKit.AccountHealthMonitor<UUID>
    /// Bad keys detected on NON-current accounts by the rotation sweep (#1777);
    /// the generic monitor only tracks the account its probe closure names.
    private var sweepUnauthorized: Set<UUID> = []
    /// The sweep task for non-current accounts; see ``start(every:)``.
    @ObservationIgnored private var sweepLoop: Task<Void, Never>?

    var unauthorizedAccountIDs: Set<UUID> {
        monitor.unauthorizedAccountIDs.union(sweepUnauthorized)
    }

    var lastChecked: Date? {
        monitor.lastChecked
    }

    private init() {
        monitor = BuddyAppKit.AccountHealthMonitor<UUID>(
            accountToCheck: {
                // The bad-key demo is intentionally checked so it surfaces the unauthorized
                // banner; the mock-data demo is skipped since it's always authorized.
                guard let account = AccountsStore.shared.currentAccount,
                      account.isBadKeyDemo || (!account.isMock && !account.apiKey.isEmpty)
                else { return nil }

                return account.id
            },
            probe: { id in
                guard let account = AccountsStore.shared.accounts.first(where: { $0.id == id }) else { return }

                // A liveness probe only needs to learn whether the key still authenticates,
                // so hit the tiny `/api/quota` endpoint rather than downloading the whole
                // org (teams + every user) every interval just to read its status code (#374).
                _ = try await account.makeClient().quota()
            },
            isUnauthorized: { ($0 as? CoderPadError)?.isUnauthorized == true }
        )
    }

    /// Re-checks the current account's key on a fixed interval (default 30 min),
    /// and sweeps every other eligible account on the same cadence: revoked
    /// credentials on a non-current account (All Accounts mode, a pinned widget)
    /// must surface without a manual account switch (#1777). Idempotent: repeated
    /// calls keep the single existing timers.
    func start(every interval: Duration = .seconds(1800)) {
        monitor.start(every: interval)
        guard sweepLoop == nil else { return }

        let interval = interval > .zero ? interval : .milliseconds(1)
        sweepLoop = Task { [weak self] in
            for await _ in AsyncTimerSequence.repeating(every: interval) {
                await self?.checkOtherAccounts()
            }
        }
    }

    // Deliberate monitor lifecycle API, kept for start/stop symmetry.
    // periphery:ignore
    func stop() {
        monitor.stop()
        sweepLoop?.cancel()
        sweepLoop = nil
    }

    func checkCurrentAccount() async {
        await monitor.check()
    }

    /// Probes every eligible non-current account's key (#1777). Sequential to keep
    /// the background load low, like the pads refresher's sweep.
    private func checkOtherAccounts() async {
        let currentID = AccountsStore.shared.currentAccount?.id
        for account in AccountsStore.shared.accounts where account.id != currentID {
            guard account.isBadKeyDemo || (!account.isMock && !account.apiKey.isEmpty) else { continue }

            do {
                _ = try await account.makeClient().quota()
                sweepUnauthorized.remove(account.id)
            } catch {
                if (error as? CoderPadError)?.isUnauthorized == true {
                    sweepUnauthorized.insert(account.id)
                }
            }
        }
        // Verdicts for removed accounts must not linger.
        let live = Set(AccountsStore.shared.accounts.map(\.id))
        sweepUnauthorized.formIntersection(live)
    }

    func isUnauthorized(_ accountID: UUID) -> Bool {
        monitor.isUnauthorized(accountID) || sweepUnauthorized.contains(accountID)
    }

    /// Clear a stale unauthorized verdict, e.g. when the account's key is changed
    /// in place. A fresh `checkCurrentAccount` re-flags it if the new key is also
    /// revoked, but until then the banner shouldn't claim the new key is bad.
    func clearUnauthorized(_ accountID: UUID) {
        monitor.clearUnauthorized(accountID)
        sweepUnauthorized.remove(accountID)
    }
}

/// Keeps the current account's pads fresh on a timer, independent of any UI.
///
/// Normal use already refreshes the cache: opening the menu bar, opening a window,
/// or switching sections all refetch. The one gap is an app left running with no
/// window open and the menu never clicked while pads change server-side — nothing
/// fetches in that state, so the Recent Pads widget and Dock badge show the last
/// snapshot until the next interaction. This closes that gap.
///
/// Writing the result through `PadsCacheStore.set` is what makes it worthwhile: that
/// cascades to the widget's shared snapshot and the active-pads Dock badge, so both
/// stay current without any window on screen.
@MainActor
final class PadsBackgroundRefresher {
    static let shared = PadsBackgroundRefresher()
    private var loop: Task<Void, Never>?
    /// Main-actor reentrancy allows a manual call or late timer tick to enter while
    /// an earlier sweep is awaiting the network. Only one sweep may own snapshots.
    private var refreshInFlight = false
    /// Per-account activity snapshots from the previous sweep, so the windowless
    /// refresher can diff and post pad-update notifications like the pad list
    /// does (#735). An account's first sweep only seeds its snapshot, so a cold
    /// start never alerts about every existing pad.
    private var previousActivity: [UUID: [String: PadActivitySnapshot]] = [:]
    private init() {}

    /// Refetches the current account's pads on a fixed interval (default 5 min).
    /// Idempotent: repeated calls keep the single existing timer. Started once at
    /// launch so it runs whether or not a window is open — unlike the per-section
    /// loads, which only fire while the UI is on screen.
    func start(every interval: Duration = .seconds(300)) {
        guard loop == nil else { return }

        // No immediate fetch (`runImmediately: false`): launch already presents a window
        // that loads the current account, so the first useful background tick is one
        // interval out.
        let interval = interval > .zero ? interval : .milliseconds(1)
        let loop = Task { [weak self] in
            for await _ in AsyncTimerSequence.repeating(every: interval) {
                await self?.refreshAllAccounts()
            }
        }
        self.loop = loop
    }

    // Deliberate monitor lifecycle API, kept for start/stop symmetry.
    // periphery:ignore
    func stop() {
        loop?.cancel()
        loop = nil
    }

    /// Refetches pads for every account a persistent consumer can need (#736): the
    /// all-accounts badge scope counts every account's cache and a widget can pin any
    /// account, so the sweep isn't limited to the current account - which is even
    /// absent in All Accounts mode, where the old current-only refresh did nothing.
    /// Sequential on purpose: one list fetch at a time keeps the background load low.
    func refreshAllAccounts() async {
        guard !refreshInFlight else { return }

        refreshInFlight = true
        defer { refreshInFlight = false }

        // Snapshots for accounts that no longer exist must not accumulate for the
        // process lifetime (#1778).
        let live = Set(AccountsStore.shared.accounts.map(\.id))
        previousActivity = previousActivity.filter { live.contains($0.key) }

        // One alert per account: the notifier coalesces onto per-account
        // identifiers (#1144, refining #1038 - the old single identifier meant
        // per-account calls cancelled each other, which forced a merged,
        // unattributed alert), so each organization's activity is named and
        // stands on its own.
        for account in AccountsStore.shared.accounts {
            // Skip mock/demo accounts (their data is static, so a refresh would only
            // churn the widget timeline) and any account without a key to fetch with.
            guard !account.isMock, !account.apiKey.isEmpty else { continue }

            let client = account.makeClient()
            guard let fetched = try? await client.listPads(sort: "updated_at,desc") else { continue }

            // The account can be removed or re-keyed while its fetch was in
            // flight; `set` would reject the stale result, but the change diff
            // and notification must not fire either (#1779).
            guard AccountsStore.shared.isCurrentClient(client, for: account.id) else { continue }

            let changes = ownedChanges(account: account, fetched: fetched)
            // `set` cascades to the widget snapshot and the active-pads Dock badge.
            PadsCacheStore.shared.set(account.id, pads: fetched, via: client)
            PadUpdateNotifier.shared.notify(changes: changes, account: account)
        }
    }

    /// The background-detected activity for one account, feeding the opt-in pad-update
    /// alerts so closing every window doesn't silently disable notifications (#735).
    /// Shares the pad list's diff/classification and its "only the user's own pads"
    /// narrowing (#424); PadUpdateNotifier itself still gates on the preference,
    /// permission, and the app being inactive.
    private func ownedChanges(account: Account, fetched: [Pad]) -> [PadChange] {
        defer { previousActivity[account.id] = PadsView.activitySnapshot(of: fetched) }
        guard let previous = previousActivity[account.id] else { return [] }

        return PadsView.padChanges(in: fetched, since: previous).filter { account.owns($0.pad.ownerEmail) }
    }
}

@Observable
final class PadActivityMonitor {
    static let shared = PadActivityMonitor()
    var unseenChangedCount: Int = 0

    private init() {}

    func record(changedCount: Int) {
        // Zero clears too: a refresh that found no changes must not leave an
        // obsolete nonzero activity indicator standing forever (#1780).
        unseenChangedCount = changedCount
    }
}
