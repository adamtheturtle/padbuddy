//
//  Accounts+Monitors.swift
//  coderpad
//
//  Observable monitors for account key health and pad activity.
//

import Foundation

@Observable
final class AccountHealthMonitor {
    static let shared = AccountHealthMonitor()

    private(set) var unauthorizedAccountIDs: Set<UUID> = []
    private(set) var lastChecked: Date?
    private var checkTask: Task<Void, Never>?

    private init() {}

    /// Re-checks the current account's key on a fixed interval (default 30 min) so a key
    /// revoked mid-session surfaces the unauthorized banner without needing a section switch.
    /// Idempotent: repeated calls keep the single existing timer.
    func start(every interval: Duration = .seconds(1800)) {
        guard checkTask == nil else { return }

        checkTask = Task { [weak self] in
            // Validate immediately so a key already revoked before launch surfaces the
            // banner now, rather than after a full interval, then re-check on the timer.
            await self?.checkCurrentAccount()
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                if Task.isCancelled { break }
                await self?.checkCurrentAccount()
            }
        }
    }

    func stop() {
        checkTask?.cancel()
        checkTask = nil
    }

    func checkCurrentAccount() async {
        // The bad-key demo is intentionally checked so it surfaces the unauthorized
        // banner; the mock-data demo is skipped since it's always authorized.
        guard let account = AccountsStore.shared.currentAccount,
              account.isBadKeyDemo || (!account.isMock && !account.apiKey.isEmpty) else { return }

        let client = account.makeClient()
        do {
            _ = try await client.organization()
            unauthorizedAccountIDs.remove(account.id)
        } catch let error as CoderPadError where error.isUnauthorized {
            unauthorizedAccountIDs.insert(account.id)
        } catch {
            // transient errors don't change auth state
        }
        lastChecked = Date()
    }

    func isUnauthorized(_ accountID: UUID) -> Bool {
        unauthorizedAccountIDs.contains(accountID)
    }

    /// Clear a stale unauthorized verdict, e.g. when the account's key is changed
    /// in place. A fresh `checkCurrentAccount` re-flags it if the new key is also
    /// revoked, but until then the banner shouldn't claim the new key is bad.
    func clearUnauthorized(_ accountID: UUID) {
        unauthorizedAccountIDs.remove(accountID)
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
final class PadsBackgroundRefresher {
    static let shared = PadsBackgroundRefresher()
    private var refreshTask: Task<Void, Never>?
    private init() {}

    /// Refetches the current account's pads on a fixed interval (default 5 min).
    /// Idempotent: repeated calls keep the single existing timer. Started once at
    /// launch so it runs whether or not a window is open — unlike the per-section
    /// loads, which only fire while the UI is on screen.
    func start(every interval: Duration = .seconds(300)) {
        guard refreshTask == nil else { return }

        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                // No immediate fetch: launch already presents a window that loads the
                // current account, so the first useful background tick is one interval out.
                try? await Task.sleep(for: interval)
                if Task.isCancelled { break }
                await self?.refreshCurrentAccount()
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
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

    func markSeen() {
        unseenChangedCount = 0
    }
}
