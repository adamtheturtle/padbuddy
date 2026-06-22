//
//  KeychainStore.swift
//  BuddyAppKit
//
//  Generic-password Keychain access with the service name injected, so each app that
//  reuses it pins its own service string (#512). Lifted from the coderpad app; the
//  legacy-keychain rationale below is preserved verbatim because it's load-bearing.
//

import Foundation
import os
import Security

public nonisolated struct KeychainStore: Sendable {
    /// The Keychain service the items are stored under. INJECTED, and a hard
    /// compatibility contract: an app must keep the same string forever or existing
    /// users lose every saved item (the items are keyed by it).
    public let service: String
    private let logger: Logger

    public init(service: String, logger: Logger) {
        self.service = service
        self.logger = logger
    }

    private func baseQuery(account: String) -> [String: Any] {
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

    public func readData(account: String) -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }

        return data
    }

    public func write(_ data: Data, account: String) {
        let query = baseQuery(account: account)
        let attrs: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            if addStatus != errSecSuccess {
                logger.error(
                    "Keychain SecItemAdd failed for account '\(account, privacy: .public)' (OSStatus \(addStatus))"
                )
            }
        } else if status != errSecSuccess {
            logger.error(
                "Keychain SecItemUpdate failed for account '\(account, privacy: .public)' (OSStatus \(status))"
            )
        }
    }

    public func delete(account: String) {
        let query = baseQuery(account: account)
        SecItemDelete(query as CFDictionary)
    }
}
