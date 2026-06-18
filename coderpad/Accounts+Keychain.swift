//
//  Accounts+Keychain.swift
//  coderpad
//
//  Keychain access for multi-account key storage.
//

import Foundation
import os
import Security

nonisolated enum Keychain {
    static let service = "com.coderpad.app"
    static let accountsAccount = "accounts"
    static let legacySingleKeyAccount = "apiKey"

    private static func baseQuery(account: String) -> [String: Any] {
        // Deliberately the legacy (file-based) keychain — NOT the data-protection keychain
        // (`kSecUseDataProtectionKeychain`). On macOS the data-protection keychain needs a
        // keychain-access-group entitlement (Keychain Sharing) or a profile's
        // application-identifier to be usable at all; this app is sandboxed but embeds no
        // profile and can't declare keychain-access-groups — that entitlement made AMFI
        // refuse to launch the notarized build (the "can't be opened" bug, see #451). With
        // neither, every data-protection SecItemAdd failed with errSecMissingEntitlement
        // (-34018, verified), silently dropping every saved account across launches (#460).
        // The legacy keychain needs no such entitlement and works for a sandboxed,
        // profile-less app. Trade-off: a Debug *rebuild* changes the code signature and so
        // re-prompts for keychain access; a stable notarized build never does.
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
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
