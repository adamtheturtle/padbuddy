//
//  Accounts+Keychain.swift
//  coderpad
//
//  Keychain access for multi-account key storage.
//

import Foundation
import os
import Security

/// App-side facade over ``KeychainStore`` (in BuddyAppKit), pinning the service name.
/// The implementation lives in the package so a sibling app can reuse it with its own
/// service; this layer keeps the call sites unchanged and, crucially, holds the
/// `com.coderpad.app` service string **byte-for-byte** — change it and every existing
/// user loses their saved accounts (the items are keyed by it). The generic account
/// store still writes this local item for the #451/#460 Developer ID constraints; this
/// facade mirrors the same account snapshot through iCloud Keychain (#678).
nonisolated enum Keychain {
    static let service = "com.coderpad.app"
    static let accountsAccount = "accounts"
    static let legacySingleKeyAccount = "apiKey"

    private static let store = KeychainStore(service: service, logger: persistenceLogger)

    static func readData(account: String) -> Data? {
        store.readData(account: account)
    }

    static func write(_ data: Data, account: String) {
        store.write(data, account: account)
    }

    static func delete(account: String) {
        store.delete(account: account)
    }

    /// Reconciles the existing local account blob with the user's iCloud Keychain copy
    /// before `AccountsStore` loads. Cloud wins when present so a fresh simulator/device
    /// gets the synced accounts; a local-only install seeds iCloud Keychain once.
    static func reconcileSyncedAccounts() {
        let local = readData(account: accountsAccount)
        let synced = readSynchronizableData(account: accountsAccount)

        if let synced {
            if local != synced {
                write(synced, account: accountsAccount)
            }
        } else if let local {
            writeSynchronizable(local, account: accountsAccount)
        }
    }

    static func mirrorAccountsToiCloudKeychain(_ data: Data?) {
        guard let data else {
            deleteSynchronizable(account: accountsAccount)
            return
        }
        writeSynchronizable(data, account: accountsAccount)
    }

    private static func synchronizableQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: true
        ]
    }

    private static func readSynchronizableData(account: String) -> Data? {
        var query = synchronizableQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }

        return data
    }

    private static func writeSynchronizable(_ data: Data, account: String) {
        let query = synchronizableQuery(account: account)
        let attrs: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            if addStatus != errSecSuccess {
                persistenceLogger.error(
                    """
                    iCloud Keychain SecItemAdd failed for account \
                    '\(account, privacy: .public)' (OSStatus \(addStatus))
                    """
                )
            }
        } else if status != errSecSuccess {
            persistenceLogger.error(
                "iCloud Keychain SecItemUpdate failed for account '\(account, privacy: .public)' (OSStatus \(status))"
            )
        }
    }

    private static func deleteSynchronizable(account: String) {
        SecItemDelete(synchronizableQuery(account: account) as CFDictionary)
    }
}
