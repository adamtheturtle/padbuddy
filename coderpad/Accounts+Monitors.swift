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
}

@Observable
final class PadActivityMonitor {
    static let shared = PadActivityMonitor()
    var unseenChangedCount: Int = 0

    private init() {}

    func record(changedCount: Int) {
        if changedCount > 0 { unseenChangedCount = changedCount }
    }

    func markSeen() {
        unseenChangedCount = 0
    }
}
