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

    var unauthorizedAccountIDs: Set<UUID> {
        monitor.unauthorizedAccountIDs
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

    /// Re-checks the current account's key on a fixed interval (default 30 min).
    /// Idempotent: repeated calls keep the single existing timer.
    func start(every interval: Duration = .seconds(1800)) {
        monitor.start(every: interval)
    }

    // Deliberate monitor lifecycle API, kept for start/stop symmetry.
    // periphery:ignore
    func stop() {
        monitor.stop()
    }

    func checkCurrentAccount() async {
        await monitor.check()
    }

    func isUnauthorized(_ accountID: UUID) -> Bool {
        monitor.isUnauthorized(accountID)
    }

    /// Clear a stale unauthorized verdict, e.g. when the account's key is changed
    /// in place. A fresh `checkCurrentAccount` re-flags it if the new key is also
    /// revoked, but until then the banner shouldn't claim the new key is bad.
    func clearUnauthorized(_ accountID: UUID) {
        monitor.clearUnauthorized(accountID)
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
                await self?.refreshCurrentAccount()
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

    func refreshCurrentAccount() async {
        // Skip mock/demo accounts (their data is static, so a refresh would only churn
        // the widget timeline) and any account without a key to fetch with.
        guard let account = AccountsStore.shared.currentAccount,
              !account.isMock, !account.apiKey.isEmpty else { return }

        let client = account.makeClient()
        guard let fetched = try? await client.listPads(sort: "updated_at,desc") else { return }

        // `set` cascades to the widget snapshot and the active-pads Dock badge.
        PadsCacheStore.shared.set(account.id, pads: fetched)
    }
}

@Observable
final class PadActivityMonitor {
    static let shared = PadActivityMonitor()
    var unseenChangedCount: Int = 0

    private init() {}

    func record(changedCount: Int) {
        if changedCount > 0 {
            unseenChangedCount = changedCount
        }
    }
}
