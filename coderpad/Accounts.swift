//
//  Accounts.swift
//  coderpad
//
//  Multi-account key storage backed by the macOS Keychain.
//

import Foundation
import os
import Security
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

struct Account: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var apiKey: String
    var isMock: Bool
    /// The email of the org member this key belongs to, used to show "my" pads.
    /// The CoderPad API doesn't expose the key's owner, so the user picks it when
    /// validating the key — and saving is gated on it (see `canSave`) — so a
    /// persisted account always has one, matching the org-users API where email is
    /// non-optional. A persisted account without one is invalid and dropped on load
    /// (see `init(from:)`). Empty only for an in-progress draft before the owner is
    /// picked.
    var userEmail: String
    /// An optional override for the CoderPad server URL, for self-hosted or regional
    /// deployments. `nil`/empty means the standard hosted endpoint. Optional so
    /// accounts saved before this existed still decode.
    var baseURL: String?
    /// An optional SF Symbol name shown in place of the name's initials on the
    /// account's avatar, so multi-account users can tell similar accounts apart at a
    /// glance. `nil` means fall back to initials. Chosen from `iconSymbolChoices`.
    var iconSymbol: String?
    /// An optional avatar tint as an "#RRGGBB" hex string. `nil` means use the
    /// default (the app accent, or purple for demo accounts). A string rather than
    /// a `Color` so it encodes cleanly into the Keychain JSON.
    var tintHex: String?

    init(id: UUID = UUID(), name: String, apiKey: String, isMock: Bool = false,
         userEmail: String = "", baseURL: String? = nil,
         iconSymbol: String? = nil, tintHex: String? = nil) {
        self.id = id
        self.name = name
        self.apiKey = apiKey
        self.isMock = isMock
        self.userEmail = userEmail
        self.baseURL = baseURL
        self.iconSymbol = iconSymbol
        self.tintHex = tintHex
    }

    enum CodingKeys: String, CodingKey {
        case id, name, apiKey, isMock, userEmail, baseURL, iconSymbol, tintHex
    }

    /// Custom decoding to enforce that a persisted account carries a user email: it's
    /// required to save (see `canSave`), so a stored account without one is invalid.
    /// Throwing here drops that single account on load (the store decodes elements
    /// leniently — see `loadAccounts`) rather than corrupting an otherwise-good account.
    /// Encoding stays synthesized.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        apiKey = try container.decode(String.self, forKey: .apiKey)
        isMock = try container.decodeIfPresent(Bool.self, forKey: .isMock) ?? false
        let email = try container.decodeIfPresent(String.self, forKey: .userEmail) ?? ""
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .userEmail, in: container,
                debugDescription: "Account has no user email; treated as invalid and skipped."
            )
        }
        userEmail = email
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL)
        iconSymbol = try container.decodeIfPresent(String.self, forKey: .iconSymbol)
        tintHex = try container.decodeIfPresent(String.self, forKey: .tintHex)
    }

    /// The curated SF Symbols offered for an account's avatar. Deliberately small
    /// and generic so the picker stays a quick visual choice rather than a search
    /// through the full symbol library.
    static let iconSymbolChoices = [
        "building.2.fill", "briefcase.fill", "person.2.fill", "house.fill",
        "star.fill", "flag.fill", "hammer.fill", "globe.americas.fill"
    ]

    /// The user-chosen avatar tint parsed from `tintHex`, or `nil` when unset or
    /// unparseable — leaving the default tint to apply.
    var tintColor: Color? {
        guard let tintHex, let color = Color(hex: tintHex) else { return nil }
        return color
    }

    /// The fallback tint when no custom color is chosen: purple for demo accounts,
    /// the app accent for real ones.
    var defaultTint: Color {
        isMock ? .purple : .accentColor
    }

    /// The tint to draw this account's avatar with: the custom color when set,
    /// otherwise `defaultTint`.
    var avatarTint: Color {
        tintColor ?? defaultTint
    }

    /// The curated tint palette offered for an account's avatar, as "#RRGGBB" hex.
    /// A small fixed set (plus the "default" option in the picker) keeps choosing a
    /// color a quick visual pick rather than a full color well.
    static let tintChoices = [
        "#3478F6", "#9B59B6", "#FF2D55", "#FF3B30",
        "#FF9500", "#34C759", "#30B0C7", "#8E8E93"
    ]

    /// The server URL to talk to: the account's override when set and parseable,
    /// otherwise the standard hosted endpoint.
    var resolvedBaseURL: URL {
        let trimmed = baseURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty, let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
           let host = url.host, !host.isEmpty {
            return url
        }
        return CoderPadClient.defaultBaseURL
    }

    /// Email of the mock data's "Demo User", who owns several of the mock pads and
    /// questions — so the demo account's "My Pads"/"My Questions" defaults return
    /// real results, and the account satisfies the required-email rule.
    static let demoUserEmail = "demo@example.com"

    static func demo() -> Account {
        Account(name: "Demo (mock data)", apiKey: "demo", isMock: true, userEmail: demoUserEmail)
    }

    /// Sentinel key marking the "bad key" demo: a mock account whose in-process
    /// server answers 401 for every request, so the unauthorized banner and error
    /// states can be demoed without a real revoked key.
    static let badKeyMockKey = "demo-bad-key"

    static func demoBadKey() -> Account {
        Account(name: "Demo (bad key)", apiKey: badKeyMockKey, isMock: true, userEmail: demoUserEmail)
    }

    /// Whether this is the bad-key demo, as opposed to the mock-data demo.
    var isBadKeyDemo: Bool {
        isMock && apiKey == Self.badKeyMockKey
    }

    /// The API client this account talks to: the in-process mock for demo accounts
    /// (answering 401 for the bad-key demo), otherwise the live hosted client.
    func makeClient() -> CoderPadClient {
        guard isMock else {
            return .live(apiKey: apiKey, baseURL: resolvedBaseURL)
        }
        return .mock(unauthorized: isBadKeyDemo)
    }

    /// A draft account pre-filled from the `CODERPAD_API_KEY` (and optional
    /// `CODERPAD_USER_EMAIL`) env vars set in the scheme's Run action, or `nil`
    /// when no key is present. Debug-only convenience so testing against real
    /// data via the Add Account button doesn't mean re-pasting the key each run;
    /// option-click the button to fill from this. Env vars are readable under the
    /// App Sandbox, unlike a home-directory dotfile — keep that scheme non-shared
    /// (xcuserdata) so the key never lands in git.
    static func fromDevEnvironment() -> Account? {
        #if DEBUG
            let env = ProcessInfo.processInfo.environment
            guard let rawKey = env["CODERPAD_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawKey.isEmpty else { return nil }
            let email = env["CODERPAD_USER_EMAIL"]?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return Account(name: "Dev (env key)", apiKey: rawKey, userEmail: email)
        #else
            return nil
        #endif
    }
}

nonisolated enum Keychain {
    static let service = "com.coderpad.app"
    static let accountsAccount = "accounts"
    static let legacySingleKeyAccount = "apiKey"

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            // Use the modern data-protection keychain so macOS doesn't prompt
            // for password on every Debug rebuild (the legacy file keychain
            // ties ACLs to the app's code signature, which changes per build).
            kSecUseDataProtectionKeychain as String: true
        ]
    }

    static func readData(account: String) -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return data
    }

    static func write(_ data: Data, account: String) {
        let query = baseQuery(account: account)
        let attrs: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            if addStatus != errSecSuccess {
                persistenceLogger.error(
                    "Keychain SecItemAdd failed for account '\(account, privacy: .public)' (OSStatus \(addStatus))"
                )
            }
        } else if status != errSecSuccess {
            persistenceLogger.error(
                "Keychain SecItemUpdate failed for account '\(account, privacy: .public)' (OSStatus \(status))"
            )
        }
    }

    static func delete(account: String) {
        let query = baseQuery(account: account)
        SecItemDelete(query as CFDictionary)
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
        if let demo = accounts.first(where: { $0.isBadKeyDemo }) {
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

    init(from decoder: Decoder) throws {
        value = try? decoder.singleValueContainer().decode(Wrapped.self)
    }
}
