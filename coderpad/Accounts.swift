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

let persistenceLogger = Logger(subsystem: "com.coderpad.app", category: "persistence")

struct Account: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var apiKey: String
    var isMock: Bool
    /// The email of the org member this key belongs to, used to show "my" pads.
    /// The CoderPad API doesn't expose the key's owner, so the user picks it when
    /// validating the key. Optional so accounts saved before this existed still decode.
    var userEmail: String?

    init(id: UUID = UUID(), name: String, apiKey: String, isMock: Bool = false, userEmail: String? = nil) {
        self.id = id
        self.name = name
        self.apiKey = apiKey
        self.isMock = isMock
        self.userEmail = userEmail
    }

    static func demo() -> Account {
        Account(name: "Demo (mock data)", apiKey: "demo", isMock: true)
    }
}

enum Keychain {
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
        let client = CoderPadClient.live(apiKey: account.apiKey)
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

@Observable
final class PadsCacheStore {
    static let shared = PadsCacheStore()
    private(set) var padsByAccount: [UUID: [Pad]] = [:]
    private init() {}
    func get(_ accountID: UUID) -> [Pad] { padsByAccount[accountID] ?? [] }
    func set(_ accountID: UUID, pads: [Pad]) { padsByAccount[accountID] = pads }
}

@Observable
final class QuestionsCacheStore {
    static let shared = QuestionsCacheStore()
    private(set) var questionsByAccount: [UUID: [Question]] = [:]
    private init() {}
    func get(_ accountID: UUID) -> [Question] { questionsByAccount[accountID] ?? [] }
    func set(_ accountID: UUID, questions: [Question]) { questionsByAccount[accountID] = questions }
}

