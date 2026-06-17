//
//  Accounts.swift
//  coderpad
//
//  Multi-account key storage backed by the macOS Keychain.
//

import Foundation
import os
import SwiftUI

nonisolated let persistenceLogger = Logger(subsystem: "com.coderpad.app", category: "persistence")

/// Serializes detached persistence writes in submission order. Without this, two
/// `Task.detached` writes issued in quick succession can finish out of order and
/// leave a stale snapshot (or an orphaned file) on disk. Each enqueued unit awaits
/// the previous one, so writes apply in the order they were submitted regardless of
/// the caller's isolation.
final class SerialWriteQueue: Sendable {
    private let tail = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)

    func enqueue(priority: TaskPriority = .utility, _ work: @Sendable @escaping () -> Void) {
        tail.withLock { current in
            let previous = current
            current = Task.detached(priority: priority) {
                await previous?.value
                work()
            }
        }
    }
}

@Observable
final class AccountsStore {
    static let shared = AccountsStore()

    var accounts: [Account] {
        didSet {
            persistAccounts()
            // Keep the widget's configuration picker in step with adds, removes, and
            // renames. Pass `accounts` directly — never `AccountsStore.shared` — since
            // the Observation macro fires this observer during init too, where touching
            // the still-initializing singleton would deadlock.
            WidgetSync.syncAccounts(accounts)
        }
    }

    var currentAccountID: UUID? {
        didSet {
            persistCurrentID()
            // Repaint the unconfigured Recent Pads widget for the newly selected
            // account from whatever pads are already cached. Uses `self` (via
            // `currentAccount`), not `AccountsStore.shared`, so it's safe when the
            // Observation macro routes this through the observer during init.
            if let account = currentAccount {
                WidgetSync.refresh(pads: PadsCacheStore.shared.get(account.id),
                                   account: account.id, isCurrent: true)
            } else {
                WidgetSync.clearCurrent()
            }
        }
    }

    var currentAccount: Account? {
        guard let id = currentAccountID else { return accounts.first }

        return accounts.first(where: { $0.id == id }) ?? accounts.first
    }

    /// Whether the user has opted into the combined "All Accounts" view, which
    /// merges pads and questions across every account into one list. Persisted like
    /// `currentAccountID`. The opt-in is only *honored* when it makes sense (two or
    /// more accounts) — see `isMergedView` — so a single-account user who once
    /// enabled it, then removed an account, silently falls back to that account.
    var showAllAccounts: Bool = false {
        didSet { persistShowAllAccounts() }
    }

    /// The accounts eligible to be merged: every configured account, including the
    /// mock/demo ones. Demo accounts are kept in so the combined view is reachable
    /// for evaluation without two real keys (e.g. "Demo" plus "Demo (bad key)",
    /// which also exercises the per-account error handling).
    var mergeableAccounts: [Account] {
        accounts
    }

    /// Whether the combined view is actually active: opted in *and* there are at
    /// least two accounts to merge. Everywhere that branches on merged mode reads
    /// this rather than `showAllAccounts`, so the merge can't engage with nothing
    /// (or only one account) to combine.
    var isMergedView: Bool {
        showAllAccounts && mergeableAccounts.count >= 2
    }

    private static let currentIDDefaultsKey = "currentAccountID"
    private static let showAllAccountsDefaultsKey = "showAllAccounts"

    /// True when launched by the UI test suite (`-uiTesting`). In this mode the store
    /// starts from a single in-memory demo account (which talks to the in-process mock
    /// server, so no network) and skips all Keychain/UserDefaults persistence — so the
    /// tests run from a deterministic state and never touch the developer's real
    /// accounts or the login keychain.
    static let isUITesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")

    private init() {
        if Self.isUITesting {
            accounts = [.demo()]
            currentAccountID = accounts.first?.id
            return
        }
        let loaded: [Account] = Self.loadAccounts() ?? []
        accounts = loaded
        if let storedID = UserDefaults.standard.string(forKey: Self.currentIDDefaultsKey),
           let uuid = UUID(uuidString: storedID),
           loaded.contains(where: { $0.id == uuid }) {
            currentAccountID = uuid
        } else {
            currentAccountID = loaded.first?.id
        }

        if loaded.isEmpty {
            migrateLegacyIfNeeded()
        }
        showAllAccounts = UserDefaults.standard.bool(forKey: Self.showAllAccountsDefaultsKey)
    }

    func add(_ account: Account) {
        accounts.append(account)
        if currentAccountID == nil { currentAccountID = account.id }
    }

    func addDemoIfMissing() {
        if !accounts.contains(where: { $0.isMock && !$0.isBadKeyDemo }) {
            add(.demo())
        }
        if let demo = accounts.first(where: { $0.isMock && !$0.isBadKeyDemo }) {
            currentAccountID = demo.id
        }
    }

    func addDemoBadKeyIfMissing() {
        if !accounts.contains(where: \.isBadKeyDemo) {
            add(.demoBadKey())
        }
        if let demo = accounts.first(where: \.isBadKeyDemo) {
            currentAccountID = demo.id
        }
    }

    func update(_ account: Account) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }

        let previous = accounts[index]
        accounts[index] = account
        // A changed key or server points at potentially different data (even a
        // different org), so the caches keyed by this id — and any stale
        // unauthorized verdict — no longer apply. Invalidate them the way
        // `remove` does, but keep the account itself; the next reload refills it.
        if previous.apiKey != account.apiKey || previous.baseURL != account.baseURL {
            PadsCacheStore.shared.remove(account.id)
            QuestionsCacheStore.shared.remove(account.id)
            OrganizationCacheStore.shared.remove(account.id)
            QuotaCacheStore.shared.remove(account.id)
            SpotlightIndexer.removeAccount(account.id)
            AccountHealthMonitor.shared.clearUnauthorized(account.id)
        }
    }

    func remove(id: UUID) {
        accounts.removeAll { $0.id == id }
        if currentAccountID == id {
            currentAccountID = accounts.first?.id
        }
        // Drop the account's cached pads/questions so a removed key leaves nothing
        // behind on disk and a re-added account starts clean.
        PadsCacheStore.shared.remove(id)
        QuestionsCacheStore.shared.remove(id)
        OrganizationCacheStore.shared.remove(id)
        QuotaCacheStore.shared.remove(id)
        SpotlightIndexer.removeAccount(id)
        AccountHealthMonitor.shared.clearUnauthorized(id)
    }

    private func migrateLegacyIfNeeded() {
        if let data = Keychain.readData(account: Keychain.legacySingleKeyAccount),
           let key = String(data: data, encoding: .utf8),
           !key.isEmpty {
            let account = Account(name: "Default", apiKey: key)
            accounts = [account]
            currentAccountID = account.id
            Keychain.delete(account: Keychain.legacySingleKeyAccount)
            return
        }
        if let legacy = UserDefaults.standard.string(forKey: "coderPadAPIKey"), !legacy.isEmpty {
            let account = Account(name: "Default", apiKey: legacy)
            accounts = [account]
            currentAccountID = account.id
            UserDefaults.standard.removeObject(forKey: "coderPadAPIKey")
        }
    }

    private static func loadAccounts() -> [Account]? {
        guard let data = Keychain.readData(account: Keychain.accountsAccount) else { return nil }

        do {
            // Decode element-by-element so a single invalid account (e.g. one persisted
            // without a user email) is dropped rather than failing the whole store and
            // taking every valid account down with it.
            return try JSONDecoder().decode([LenientElement<Account>].self, from: data)
                .compactMap(\.value)
        } catch {
            let reason = error.localizedDescription
            persistenceLogger.error(
                "Failed to decode accounts from Keychain, saved keys may be unreadable: \(reason, privacy: .public)"
            )
            return nil
        }
    }

    private let writeQueue = SerialWriteQueue()

    private func persistAccounts() {
        guard !Self.isUITesting else { return }

        let snapshot = accounts
        // Move Keychain I/O off the main thread to keep the UI responsive, but keep
        // writes ordered so a slower earlier write can't overwrite a newer snapshot.
        writeQueue.enqueue(priority: .userInitiated) {
            if snapshot.isEmpty {
                Keychain.delete(account: Keychain.accountsAccount)
                return
            }
            do {
                let data = try JSONEncoder().encode(snapshot)
                Keychain.write(data, account: Keychain.accountsAccount)
            } catch {
                let reason = error.localizedDescription
                persistenceLogger.error("Failed to encode accounts snapshot: \(reason, privacy: .public)")
            }
        }
    }

    private func persistCurrentID() {
        guard !Self.isUITesting else { return }

        if let id = currentAccountID {
            UserDefaults.standard.set(id.uuidString, forKey: Self.currentIDDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.currentIDDefaultsKey)
        }
    }

    private func persistShowAllAccounts() {
        guard !Self.isUITesting else { return }

        UserDefaults.standard.set(showAllAccounts, forKey: Self.showAllAccountsDefaultsKey)
    }
}

/// Wraps a decodable element so a per-element decode failure yields `nil` instead of
/// aborting the whole array — letting `loadAccounts` drop an individual invalid account
/// while keeping the rest.
struct LenientElement<Wrapped: Decodable>: Decodable {
    let value: Wrapped?

    init(from decoder: any Decoder) {
        value = try? decoder.singleValueContainer().decode(Wrapped.self)
    }
}
