//
//  Secrets.swift
//  coderpad
//
//  Multi-account key storage backed by the macOS Keychain.
//

import Foundation
import Security
import SwiftUI

struct Account: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var apiKey: String
    var isMock: Bool

    init(id: UUID = UUID(), name: String, apiKey: String, isMock: Bool = false) {
        self.id = id
        self.name = name
        self.apiKey = apiKey
        self.isMock = isMock
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
            SecItemAdd(insert as CFDictionary, nil)
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
        return try? JSONDecoder().decode([Account].self, from: data)
    }

    private func persistAccounts() {
        if accounts.isEmpty {
            Keychain.delete(account: Keychain.accountsAccount)
            return
        }
        if let data = try? JSONEncoder().encode(accounts) {
            Keychain.write(data, account: Keychain.accountsAccount)
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
final class PinnedPadsStore {
    static let shared = PinnedPadsStore()

    private(set) var pinnedByAccount: [String: Set<String>] = [:]
    private static let defaultsKey = "pinnedPads"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([String: Set<String>].self, from: data) {
            pinnedByAccount = decoded
        }
    }

    func isPinned(padID: String, accountID: UUID) -> Bool {
        pinnedByAccount[accountID.uuidString]?.contains(padID) ?? false
    }

    func togglePinned(padID: String, accountID: UUID) {
        var set = pinnedByAccount[accountID.uuidString] ?? []
        if set.contains(padID) { set.remove(padID) } else { set.insert(padID) }
        pinnedByAccount[accountID.uuidString] = set
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(pinnedByAccount) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
