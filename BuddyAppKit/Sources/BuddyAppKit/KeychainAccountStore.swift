//
//  KeychainAccountStore.swift
//  BuddyAppKit
//
//  A generic multi-account store backed by the Keychain (accounts) + UserDefaults
//  (selection and the merged-view opt-in), extracted from the coderpad app (#513) so a
//  sibling app can reuse it. All app-specific behaviour — serialization, widget
//  mirroring, cache teardown on remove/rekey, the testing seed, legacy migration — is
//  injected through ``Config``, so this type knows nothing about any particular service.
//

import Foundation
import os

/// The minimum an account model must provide to live in ``KeychainAccountStore``.
/// Deliberately requires only two nonisolated members — NOT `Codable`/`Hashable`/
/// `Identifiable` — so a MainActor-default app whose model has main-actor-isolated
/// conformances can still satisfy it. Serialization is injected through ``Config``
/// (and runs on the main actor, where the model's `Codable` lives) instead.
public protocol StorableAccount {
    /// The account's stable per-device identifier.
    var accountID: UUID { get }
    /// Whether `self` talks to a different backend than `other` (a changed key or
    /// server), so the store can fire `onRekeyed` to invalidate now-stale caches.
    func pointsAtDifferentBackend(than other: Self) -> Bool
}

@Observable
@MainActor
public final class KeychainAccountStore<Account: StorableAccount> {
    /// The injected serialization, side-effects, and storage keys that adapt the generic
    /// store to a particular app. Closures run on the main actor (the store is
    /// main-actor bound), so the account model's main-actor-isolated `Codable` is usable
    /// inside `encode`/`decode`.
    public struct Config {
        public var keychain: KeychainStore
        public var accountsKey: String
        public var currentIDDefaultsKey: String
        public var showAllAccountsDefaultsKey: String
        public var encode: @MainActor ([Account]) -> Data?
        public var decode: @MainActor (Data) -> [Account]
        /// True under the app's UI-testing launch: the store seeds from `seedForTesting`
        /// and skips ALL persistence, so tests run from a deterministic state and never
        /// touch real accounts or the login keychain.
        public var isTestingMode: Bool
        public var seedForTesting: @MainActor () -> [Account]
        /// One-time migration from older storage, run only when no accounts load and not
        /// testing. Returns the migrated accounts (and performs its own cleanup), or nil.
        public var migrateIfEmpty: @MainActor () -> [Account]?
        public var onAccountsChanged: @MainActor ([Account]) -> Void
        public var onCurrentChanged: @MainActor (Account?) -> Void
        public var onRemoved: @MainActor (UUID) -> Void
        public var onRekeyed: @MainActor (UUID) -> Void
        public var logger: Logger

        public init(
            keychain: KeychainStore,
            accountsKey: String,
            currentIDDefaultsKey: String,
            showAllAccountsDefaultsKey: String,
            encode: @escaping @MainActor ([Account]) -> Data?,
            decode: @escaping @MainActor (Data) -> [Account],
            isTestingMode: Bool,
            seedForTesting: @escaping @MainActor () -> [Account],
            migrateIfEmpty: @escaping @MainActor () -> [Account]?,
            onAccountsChanged: @escaping @MainActor ([Account]) -> Void,
            onCurrentChanged: @escaping @MainActor (Account?) -> Void,
            onRemoved: @escaping @MainActor (UUID) -> Void,
            onRekeyed: @escaping @MainActor (UUID) -> Void,
            logger: Logger
        ) {
            self.keychain = keychain
            self.accountsKey = accountsKey
            self.currentIDDefaultsKey = currentIDDefaultsKey
            self.showAllAccountsDefaultsKey = showAllAccountsDefaultsKey
            self.encode = encode
            self.decode = decode
            self.isTestingMode = isTestingMode
            self.seedForTesting = seedForTesting
            self.migrateIfEmpty = migrateIfEmpty
            self.onAccountsChanged = onAccountsChanged
            self.onCurrentChanged = onCurrentChanged
            self.onRemoved = onRemoved
            self.onRekeyed = onRekeyed
            self.logger = logger
        }
    }

    public var accounts: [Account] {
        didSet {
            persistAccounts()
            // Pass `accounts` directly — never the shared singleton — since the
            // Observation macro fires this observer during init too, where reaching back
            // into the still-initializing singleton would deadlock.
            config.onAccountsChanged(accounts)
        }
    }

    private var selectedAccountID: UUID?

    public var currentAccountID: UUID? {
        get { selectedAccountID }
        set {
            // Keep the selection identifier and resolved account atomic: an invalid
            // runtime assignment selects the first available account (or nil), just
            // as initialization does, and only that canonical value is published.
            selectedAccountID = newValue.flatMap { requested in
                accounts.contains { $0.accountID == requested } ? requested : accounts.first?.accountID
            }
            persistCurrentID()
            // Hand the resolved current account (computed from self, not the singleton)
            // to the app so it can repaint the widget; safe during init for the same
            // reason as above.
            config.onCurrentChanged(currentAccount)
        }
    }

    public var currentAccount: Account? {
        guard let id = currentAccountID else { return accounts.first }

        return accounts.first { $0.accountID == id }
    }

    /// Whether the user opted into the combined "All Accounts" view. Only *honoured*
    /// when it makes sense (see ``isMergedView``), so a single-account user who once
    /// enabled it silently falls back to that account.
    public var showAllAccounts = false {
        didSet { persistShowAllAccounts() }
    }

    /// Every configured account, eligible to be merged.
    public var mergeableAccounts: [Account] {
        accounts
    }

    /// Whether the combined view is actually active: opted in *and* at least two
    /// accounts to merge. Everything that branches on merged mode reads this.
    public var isMergedView: Bool {
        showAllAccounts && mergeableAccounts.count >= 2
    }

    @ObservationIgnored private let config: Config
    @ObservationIgnored private let writeQueue = SerialWriteQueue()

    public init(config: Config) {
        self.config = config
        if config.isTestingMode {
            accounts = Self.deduplicated(config.seedForTesting())
            currentAccountID = accounts.first?.accountID
            return
        }
        let load = Self.loadAccounts(config: config)
        let loaded = Self.deduplicated(load.accounts)
        accounts = loaded
        if let stored = UserDefaults.standard.string(forKey: config.currentIDDefaultsKey),
           let uuid = UUID(uuidString: stored),
           loaded.contains(where: { $0.accountID == uuid }) {
            currentAccountID = uuid
        } else {
            currentAccountID = loaded.first?.accountID
        }

        if loaded.isEmpty, load.shouldMigrate {
            let migrated = Self.deduplicated(config.migrateIfEmpty() ?? [])
            if !migrated.isEmpty {
                accounts = migrated
                currentAccountID = migrated.first?.accountID
            }
        }
        showAllAccounts = UserDefaults.standard.bool(forKey: config.showAllAccountsDefaultsKey)
    }

    public func add(_ account: Account) {
        if accounts.contains(where: { $0.accountID == account.accountID }) {
            update(account)
            return
        }
        accounts.append(account)
        if currentAccountID == nil {
            currentAccountID = account.accountID
        }
    }

    public func update(_ account: Account) {
        guard let index = accounts.firstIndex(where: { $0.accountID == account.accountID }) else { return }

        let previous = accounts[index]
        // A changed key or server points at potentially different data (even a different
        // org), so invalidate caches before publishing the replacement to observers.
        if account.pointsAtDifferentBackend(than: previous) {
            config.onRekeyed(account.accountID)
        }
        accounts[index] = account
    }

    public func remove(id: UUID) {
        guard accounts.contains(where: { $0.accountID == id }) else { return }

        // Tear down account-scoped caches/routes before either observed property
        // publishes its new value. Otherwise observers can begin rendering the next
        // selection while resources belonging to the removed account still exist
        // (#1284).
        config.onRemoved(id)
        accounts.removeAll { $0.accountID == id }
        if currentAccountID == id {
            currentAccountID = accounts.first?.accountID
        }
    }

    private static func loadAccounts(config: Config) -> (accounts: [Account], shouldMigrate: Bool) {
        let readResult = config.keychain.readResult(account: config.accountsKey)
        if case let .failure(status) = readResult {
            config.logger.error("Keychain account read failed (OSStatus \(status)); suppressing migration")
        }
        return decodedAccounts(from: readResult, decode: config.decode)
    }

    static func decodedAccounts(
        from result: KeychainReadResult,
        decode: @MainActor (Data) -> [Account]
    ) -> (accounts: [Account], shouldMigrate: Bool) {
        switch result {
        case let .value(data):
            (decode(data), false)
        case .notFound:
            ([], true)
        case .failure:
            ([], false)
        }
    }

    private static func deduplicated(_ accounts: [Account]) -> [Account] {
        var seen = Set<UUID>()
        return accounts.filter { seen.insert($0.accountID).inserted }
    }

    private func persistAccounts() {
        guard !config.isTestingMode else { return }

        let keychain = config.keychain
        let key = config.accountsKey
        // Encode on the main actor (where the account model's Codable conformance lives),
        // then hand only the resulting `Data` to the background write — so the account
        // model never has to cross actors. Writes stay ordered via the queue so a slower
        // earlier write can't overwrite a newer snapshot.
        if accounts.isEmpty {
            writeQueue.enqueue(priority: .userInitiated, coalescingKey: "accounts") {
                keychain.delete(account: key)
            }
            return
        }
        guard let data = config.encode(accounts) else {
            config.logger.error("Failed to encode accounts snapshot")
            return
        }

        writeQueue.enqueue(priority: .userInitiated, coalescingKey: "accounts") {
            keychain.write(data, account: key)
        }
    }

    private func persistCurrentID() {
        guard !config.isTestingMode else { return }

        if let id = currentAccountID {
            UserDefaults.standard.set(id.uuidString, forKey: config.currentIDDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: config.currentIDDefaultsKey)
        }
    }

    private func persistShowAllAccounts() {
        guard !config.isTestingMode else { return }

        UserDefaults.standard.set(showAllAccounts, forKey: config.showAllAccountsDefaultsKey)
    }
}
