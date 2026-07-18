//
//  Accounts.swift
//  coderpad
//
//  Multi-account key storage backed by the macOS Keychain.
//

import Foundation
import os

nonisolated let persistenceLogger = Logger(subsystem: "com.coderpad.app", category: "persistence")

/// True under the app's UI-testing launch (`-uiTesting`): the store seeds a single
/// in-memory demo account and skips all persistence. Read in a couple of places besides
/// the store (e.g. window sizing), so it's a shared global.
let coderpadIsUITesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")

/// True when this process is the unit-test host (XCTest injected a test bundle into
/// the app). The app then renders a placeholder instead of the full UI and skips
/// launch side effects, so live account/cache loading can't race test execution -
/// a use-after-free in that race crashed the host a few seconds into every full
/// suite run, failing all in-flight tests (#978). UI tests are unaffected: the
/// tested app is a separate process with no XCTest configuration in its environment.
let coderpadIsHostingUnitTests: Bool = {
    let environment = ProcessInfo.processInfo.environment
    return environment["XCTestConfigurationFilePath"] != nil
        || environment["XCTestBundlePath"] != nil
        || environment["XCTestSessionIdentifier"] != nil
}()

/// The app's account store is the generic ``KeychainAccountStore`` (BuddyAppKit, #513)
/// specialised to ``Account``; the typealias + a `shared` accessor keep every call site
/// unchanged while the storage mechanics live in the shared package.
typealias AccountsStore = KeychainAccountStore<Account>

/// The single shared store, configured with the coderpad-specific keys and side-effects.
private let coderpadAccountStore = KeychainAccountStore<Account>(config: makeCoderpadConfig())

extension KeychainAccountStore where Account == CoderPad.Account {
    static var shared: KeychainAccountStore<Account> {
        coderpadAccountStore
    }

    /// Preserved for the few non-store call sites (e.g. the UI-testing window sizing).
    static var isUITesting: Bool {
        coderpadIsUITesting
    }

    /// Adds the demo account if it isn't present, then selects it. Demo accounts are
    /// app-specific sentinels, so this stays out of the generic store.
    func addDemoIfMissing() {
        if !accounts.contains(where: { $0.isMock && !$0.isBadKeyDemo }) {
            add(.demo())
        }
        if let demo = accounts.first(where: { $0.isMock && !$0.isBadKeyDemo }) {
            currentAccountID = demo.id
        }
    }

    /// The stored account whose credentials `client` was built from. Views handed a
    /// client directly (standalone pad windows, merged rows) can belong to a
    /// non-current account, so account-scoped reads and writes must resolve the
    /// owner from the client identity rather than assume the globally current
    /// account (#873, #986). Nil when no stored account matches byte-for-byte
    /// (e.g. mock clients).
    func account(matching client: CoderPadClient) -> Account? {
        accounts.first {
            $0.apiKey.trimmingCharacters(in: .whitespacesAndNewlines) == client.apiKey
                && $0.resolvedBaseURL == client.baseURL
        }
    }

    /// True when `client`'s credentials are still exactly what account `accountID`
    /// resolves to. Cache setters use this to reject results from loads that
    /// outlived an account removal or re-key (#754): a loader's client embeds the
    /// credentials it fetched with, so a removed account (no id) or a re-keyed one
    /// (different key/server) fails the comparison and the late result is dropped
    /// instead of resurrecting purged data. Compares against `makeClient()` rather
    /// than the raw stored fields so mock/demo clients (whose identity is derived,
    /// not stored) validate the same way real ones do.
    func isCurrentClient(_ client: CoderPadClient, for accountID: UUID) -> Bool {
        guard let account = accounts.first(where: { $0.id == accountID }) else { return false }

        let current = account.makeClient()
        return current.baseURL == client.baseURL && current.apiKey == client.apiKey
    }

    func addDemoBadKeyIfMissing() {
        if !accounts.contains(where: \.isBadKeyDemo) {
            add(.demoBadKey())
        }
        if let demo = accounts.first(where: \.isBadKeyDemo) {
            currentAccountID = demo.id
        }
    }
}

extension Account: StorableAccount {
    nonisolated var accountID: UUID {
        id
    }

    /// A changed API key or server points at a potentially different backend (even a
    /// different org), so the store invalidates this account's caches on update.
    nonisolated func pointsAtDifferentBackend(than other: Account) -> Bool {
        apiKey != other.apiKey || baseURL != other.baseURL
    }
}

/// Builds the coderpad-specific store configuration: the `com.coderpad.app` Keychain
/// service and cache keys, the UI-testing seed, the legacy migration, and the
/// widget/cache side-effects the generic store fires.
@MainActor private func makeCoderpadConfig() -> KeychainAccountStore<Account>.Config {
    if !coderpadIsUITesting {
        Keychain.reconcileSyncedAccounts()
    }

    return KeychainAccountStore<Account>.Config(
        keychain: KeychainStore(service: Keychain.service, logger: persistenceLogger),
        accountsKey: Keychain.accountsAccount,
        currentIDDefaultsKey: "currentAccountID",
        showAllAccountsDefaultsKey: "showAllAccounts",
        encode: { try? JSONEncoder().encode($0) },
        // Decode element-by-element so a single corrupt account is dropped rather
        // than failing the whole store.
        decode: { (try? JSONDecoder().decode([LenientElement<Account>].self, from: $0))?.compactMap(\.value) ?? [] },
        isTestingMode: coderpadIsUITesting,
        seedForTesting: { [.demo()] },
        migrateIfEmpty: migrateLegacyAccounts,
        onAccountsChanged: { accounts in
            if !coderpadIsUITesting {
                Keychain.mirrorAccountsToiCloudKeychain(try? JSONEncoder().encode(accounts))
            }
            // Keep the widget's configuration picker in step with adds, removes, and
            // renames. Takes the array directly — the Observation macro fires this during
            // the store's init, where reaching back into the singleton would deadlock.
            WidgetSync.syncAccounts(accounts)
            // Purge the client-keyed caches of any account that just vanished or
            // changed credentials (#718, #883, #884).
            ClientCacheTeardown.reconcile(accounts)
        },
        onCurrentChanged: { account in
            // Repaint the unconfigured Recent Pads widget for the newly selected account
            // from whatever pads are already cached.
            if let account {
                WidgetSync.refresh(pads: PadsCacheStore.shared.get(account.id),
                                   account: account.id, isCurrent: true)
            } else {
                WidgetSync.clearCurrent()
            }
        },
        // Re-key shares the removal teardown but must not tombstone the widget
        // snapshot: the account persists, so the tombstone would block every
        // future widget refresh (#1022). The hooks hand over the full removed /
        // previous account (buddy-kit 0.15.0); teardown is keyed by its id.
        onRemoved: { tearDownAccountData($0.id, isRekey: false) },
        onRekeyed: { tearDownAccountData($0.id, isRekey: true) },
        logger: persistenceLogger
    )
}

/// One-time migration from the app's older single-key storage (a lone Keychain key,
/// then before that a UserDefaults key) into the multi-account store. Returns the
/// migrated account and clears the legacy storage, or nil when there's nothing to do.
@MainActor private func migrateLegacyAccounts() -> [Account]? {
    if let data = Keychain.readData(account: Keychain.legacySingleKeyAccount),
       let key = String(data: data, encoding: .utf8),
       !key.isEmpty {
        Keychain.delete(account: Keychain.legacySingleKeyAccount)
        return [Account(name: "Default", apiKey: key)]
    }
    if let legacy = UserDefaults.standard.string(forKey: "coderPadAPIKey"), !legacy.isEmpty {
        UserDefaults.standard.removeObject(forKey: "coderPadAPIKey")
        return [Account(name: "Default", apiKey: legacy)]
    }
    return nil
}

/// Drops everything keyed by a removed or re-keyed account: the network caches, the
/// Spotlight index, the cached unauthorized verdict, and the personal data (favorites,
/// pad-open history) — so a removed key leaves nothing behind
/// and a re-keyed account (possibly a different org) can't re-attach stale per-org data
/// (a leftover favorite id could even reattach to an unrelated question). #379
///
/// The caches keyed by client identity rather than account id are purged separately by
/// ``ClientCacheTeardown``, which recovers the removed account's old credentials.
@MainActor private func tearDownAccountData(_ id: UUID, isRekey: Bool) {
    PadsCacheStore.shared.remove(id, isRekey: isRekey)
    QuestionsCacheStore.shared.remove(id)
    OrganizationCacheStore.shared.remove(id)
    QuotaCacheStore.shared.remove(id)
    SpotlightIndexer.removeAccount(id)
    AccountHealthMonitor.shared.clearUnauthorized(id)
    FavoritePadsStore.shared.remove(account: id)
    FavoriteQuestionsStore.shared.remove(account: id)
    FavoritesOrderStore.shared.remove(account: id)
    PadOpenedStore.shared.remove(account: id)
    AccountScopedDefaults.purge(account: id)
    InlineEditDrafts.shared.removeAll(account: id)
}

/// Purges the client-keyed caches — cached organization members (and the API key
/// embedded in the cache key), any in-flight organization fetch, and every cached
/// pad detail, candidate code included — when an account disappears or changes
/// credentials. Those caches are keyed by server + API key, but the store's
/// remove/rekey hooks deliver only the account id, after the old value is already
/// gone. So this watches the accounts array itself, diffing each change against
/// the previous snapshot to recover the vanished credentials (#718, #883, #884, #719).
@MainActor
enum ClientCacheTeardown {
    private struct Identity: Hashable {
        let baseURL: URL
        let apiKey: String
    }

    private static var lastKnown: [UUID: Identity] = [:]

    static func reconcile(_ accounts: [Account]) {
        var current: [UUID: Identity] = [:]
        for account in accounts {
            let client = account.makeClient()
            current[account.id] = Identity(baseURL: client.baseURL, apiKey: client.apiKey)
        }
        // The first call (during the store's init) sees an empty snapshot, so a
        // fresh launch purges nothing.
        for (id, previous) in lastKnown where current[id] != previous {
            OrganizationCacheStore.shared.remove(baseURL: previous.baseURL, apiKey: previous.apiKey)
            PadDetailCacheStore.shared.remove(baseURL: previous.baseURL, apiKey: previous.apiKey)
        }
        lastKnown = current
    }
}

/// Purges every per-account UserDefaults key on account removal or re-key: live
/// filters, selected rows, scroll positions, and the last-open section all persist
/// under keys embedding the account UUID, and they carry org-specific emails, team
/// names, search text, and per-org item ids. Left behind, a re-keyed UUID pointing
/// at a different org re-applies the old org's filters and can restore an unrelated
/// same-numbered question (#914). Sweeping by UUID substring covers every such key,
/// including ones added later, without maintaining a list here.
nonisolated enum AccountScopedDefaults {
    static func purge(account: UUID, defaults: UserDefaults = .standard) {
        for key in defaults.dictionaryRepresentation().keys where key.contains(account.uuidString) {
            defaults.removeObject(forKey: key)
        }
    }
}
