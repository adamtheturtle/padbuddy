//
//  Secrets.swift
//  coderpad
//
//  Multi-account key storage backed by the macOS Keychain.
//

import Foundation
import Security
import SwiftUI
import os.log

nonisolated let persistenceLogger = Logger(subsystem: "com.coderpad.app", category: "persistence")

struct Account: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var apiKey: String
    var isMock: Bool
    /// The email of the org member this key belongs to, used to show "my" pads.
    /// The CoderPad API doesn't expose the key's owner, so the user picks it when
    /// validating the key. Optional so accounts saved before this existed still decode.
    var userEmail: String?
    /// An optional override for the CoderPad server URL, for self-hosted or regional
    /// deployments. `nil`/empty means the standard hosted endpoint. Optional so
    /// accounts saved before this existed still decode.
    var baseURL: String?

    init(id: UUID = UUID(), name: String, apiKey: String, isMock: Bool = false, userEmail: String? = nil, baseURL: String? = nil) {
        self.id = id
        self.name = name
        self.apiKey = apiKey
        self.isMock = isMock
        self.userEmail = userEmail
        self.baseURL = baseURL
    }

    /// The server URL to talk to: the account's override when set and parseable,
    /// otherwise the standard hosted endpoint.
    var resolvedBaseURL: URL {
        let trimmed = baseURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty, let url = URL(string: trimmed), url.scheme != nil {
            return url
        }
        return CoderPadClient.defaultBaseURL
    }

    static func demo() -> Account {
        Account(name: "Demo (mock data)", apiKey: "demo", isMock: true)
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
        let trimmedEmail = env["CODERPAD_USER_EMAIL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let email = (trimmedEmail?.isEmpty == false) ? trimmedEmail : nil
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
            kSecUseDataProtectionKeychain as String: true,
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
                persistenceLogger.error("Keychain SecItemAdd failed for account '\(account, privacy: .public)' (OSStatus \(addStatus))")
            }
        } else if status != errSecSuccess {
            persistenceLogger.error("Keychain SecItemUpdate failed for account '\(account, privacy: .public)' (OSStatus \(status))")
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
        didSet { persistAccounts() }
    }

    var currentAccountID: UUID? {
        didSet { persistCurrentID() }
    }

    var currentAccount: Account? {
        guard let id = currentAccountID else { return accounts.first }
        return accounts.first(where: { $0.id == id }) ?? accounts.first
    }

    private static let currentIDDefaultsKey = "currentAccountID"

    private init() {
        let loaded: [Account] = Self.loadAccounts() ?? []
        accounts = loaded
        if let s = UserDefaults.standard.string(forKey: Self.currentIDDefaultsKey),
           let uuid = UUID(uuidString: s),
           loaded.contains(where: { $0.id == uuid }) {
            currentAccountID = uuid
        } else {
            currentAccountID = loaded.first?.id
        }

        if loaded.isEmpty {
            migrateLegacyIfNeeded()
        }

    }

    func add(_ account: Account) {
        accounts.append(account)
        if currentAccountID == nil { currentAccountID = account.id }
    }

    func addDemoIfMissing() {
        if !accounts.contains(where: { $0.isMock }) {
            add(.demo())
        }
        if let demo = accounts.first(where: { $0.isMock }) {
            currentAccountID = demo.id
        }
    }

    func update(_ account: Account) {
        if let i = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[i] = account
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
            return try JSONDecoder().decode([Account].self, from: data)
        } catch {
            persistenceLogger.error("Failed to decode accounts from Keychain — saved keys may be unreadable: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func persistAccounts() {
        let snapshot = accounts
        // Move Keychain I/O off the main thread to keep the UI responsive.
        Task.detached(priority: .userInitiated) {
            if snapshot.isEmpty {
                Keychain.delete(account: Keychain.accountsAccount)
                return
            }
            do {
                let data = try JSONEncoder().encode(snapshot)
                Keychain.write(data, account: Keychain.accountsAccount)
            } catch {
                persistenceLogger.error("Failed to encode accounts snapshot: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func persistCurrentID() {
        if let id = currentAccountID {
            UserDefaults.standard.set(id.uuidString, forKey: Self.currentIDDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.currentIDDefaultsKey)
        }
    }
}

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
        guard let account = AccountsStore.shared.currentAccount,
              !account.isMock,
              !account.apiKey.isEmpty else { return }
        let client = CoderPadClient.live(apiKey: account.apiKey, baseURL: account.resolvedBaseURL)
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

struct NamedSearch: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var search: String
    var stateFilter: String?
    var languageFilter: String?
    var ownerFilter: String?
    var teamFilter: String?
    var typeFilter: String?
    var dateRangeFilter: String?

    init(id: UUID = UUID(), name: String,
         search: String = "",
         stateFilter: String? = nil, languageFilter: String? = nil,
         ownerFilter: String? = nil, teamFilter: String? = nil,
         typeFilter: String? = nil, dateRangeFilter: String? = nil) {
        self.id = id
        self.name = name
        self.search = search
        self.stateFilter = stateFilter
        self.languageFilter = languageFilter
        self.ownerFilter = ownerFilter
        self.teamFilter = teamFilter
        self.typeFilter = typeFilter
        self.dateRangeFilter = dateRangeFilter
    }
}

@Observable
final class SavedSearchStore {
    static let shared = SavedSearchStore()
    private(set) var searches: [NamedSearch] = []
    private static let key = "savedPadSearches.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([NamedSearch].self, from: data) {
            searches = decoded
        }
    }

    func add(_ search: NamedSearch) {
        searches.append(search)
        save()
    }

    func remove(id: UUID) {
        searches.removeAll { $0.id == id }
        save()
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(searches)
            UserDefaults.standard.set(data, forKey: Self.key)
        } catch {
            persistenceLogger.error("Failed to encode saved searches: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// On-disk backing for the per-account list caches. Lets pads and questions a
/// returning user already loaded appear instantly on the next cold launch, with
/// the network fetch refreshing them in the background (stale-while-revalidate).
///
/// Snapshots live in Application Support, one JSON file per account+kind. The
/// encoder/decoder pair is symmetric (default strategies), so it round-trips the
/// API models faithfully without depending on the API's date format.
enum CacheDisk {
    // nonisolated so reads/writes genuinely run off the main actor when invoked
    // from a detached task, rather than hopping back to the main thread.
    private nonisolated static let logger = Logger(subsystem: "com.coderpad.app", category: "cache")

    private nonisolated static func url(kind: String, account: UUID) -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("com.coderpad.app/DataCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(kind)-\(account.uuidString).json")
    }

    nonisolated static func load<T: Decodable>(_ type: T.Type, kind: String, account: UUID) -> T? {
        guard let url = url(kind: kind, account: account),
              let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            logger.error("Failed to decode \(kind, privacy: .public) cache: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    nonisolated static func save<T: Encodable>(_ value: T, kind: String, account: UUID) {
        guard let url = url(kind: kind, account: account) else { return }
        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            logger.error("Failed to write \(kind, privacy: .public) cache: \(error.localizedDescription, privacy: .public)")
        }
    }

    nonisolated static func delete(kind: String, account: UUID) {
        guard let url = url(kind: kind, account: account) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

@Observable
final class PadsCacheStore {
    static let shared = PadsCacheStore()
    private(set) var padsByAccount: [UUID: [Pad]] = [:]
    /// Accounts whose disk snapshot we've already consulted, so a genuinely empty
    /// cache isn't re-read from disk on every `get`.
    private var diskConsulted: Set<UUID> = []
    private init() {}

    func get(_ accountID: UUID) -> [Pad] {
        if let cached = padsByAccount[accountID] { return cached }
        if !diskConsulted.contains(accountID) {
            diskConsulted.insert(accountID)
            if let disk = CacheDisk.load([Pad].self, kind: "pads", account: accountID) {
                padsByAccount[accountID] = disk
                return disk
            }
        }
        return []
    }

    /// `persist: false` updates only the in-memory snapshot, skipping the disk write —
    /// used when streaming pages so intermediate snapshots warm the UI without churning
    /// the disk; the caller persists once with the final, complete list.
    func set(_ accountID: UUID, pads: [Pad], persist: Bool = true) {
        padsByAccount[accountID] = pads
        diskConsulted.insert(accountID)
        guard persist else { return }
        Task.detached(priority: .utility) {
            CacheDisk.save(pads, kind: "pads", account: accountID)
        }
    }

    func remove(_ accountID: UUID) {
        padsByAccount[accountID] = nil
        diskConsulted.remove(accountID)
        Task.detached(priority: .utility) {
            CacheDisk.delete(kind: "pads", account: accountID)
        }
    }
}

@Observable
final class QuestionsCacheStore {
    static let shared = QuestionsCacheStore()
    private(set) var questionsByAccount: [UUID: [Question]] = [:]
    private var diskConsulted: Set<UUID> = []
    private init() {}

    func get(_ accountID: UUID) -> [Question] {
        if let cached = questionsByAccount[accountID] { return cached }
        if !diskConsulted.contains(accountID) {
            diskConsulted.insert(accountID)
            if let disk = CacheDisk.load([Question].self, kind: "questions", account: accountID) {
                questionsByAccount[accountID] = disk
                return disk
            }
        }
        return []
    }

    func set(_ accountID: UUID, questions: [Question]) {
        questionsByAccount[accountID] = questions
        diskConsulted.insert(accountID)
        Task.detached(priority: .utility) {
            CacheDisk.save(questions, kind: "questions", account: accountID)
        }
    }

    func remove(_ accountID: UUID) {
        questionsByAccount[accountID] = nil
        diskConsulted.remove(accountID)
        Task.detached(priority: .utility) {
            CacheDisk.delete(kind: "questions", account: accountID)
        }
    }
}

