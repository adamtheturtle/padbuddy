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

public nonisolated enum KeychainReadResult: Sendable, Equatable {
    case value(Data)
    case notFound
    case failure(OSStatus)
}

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

    public func readResult(account: String) -> KeychainReadResult {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return .notFound
        }
        guard status == errSecSuccess else { return .failure(status) }
        guard let data = item as? Data else { return .failure(errSecDecode) }

        refreshDebugBuildAccessIfNeeded(account: account)

        return .value(data)
    }

    /// Compatibility convenience for callers where missing and unreadable have the
    /// same fallback. Account loading uses `readResult` so it can avoid destructive
    /// migration after an access failure (#1287).
    public func readData(account: String) -> Data? {
        guard case let .value(data) = readResult(account: account) else { return nil }

        return data
    }

    public func write(_ data: Data, account: String) {
        let query = baseQuery(account: account)
        let attrs: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            applyDebugBuildAccess(to: &insert, account: account)
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

    #if DEBUG
    private func refreshDebugBuildAccessIfNeeded(account: String) {
        guard !debugBuildAccessAlreadyPermitsAnyApp(account: account),
              let access = makeDebugBuildAccess(account: account) else { return }

        let attrs: [String: Any] = [kSecAttrAccess as String: access]
        let status = SecItemUpdate(baseQuery(account: account) as CFDictionary, attrs as CFDictionary)
        if status != errSecSuccess {
            logger.error(
                "Keychain SecItemUpdate failed while refreshing debug access for account '\(account, privacy: .public)' (OSStatus \(status))"
            )
        }
    }

    private func applyDebugBuildAccess(to item: inout [String: Any], account: String) {
        guard let access = makeDebugBuildAccess(account: account) else { return }
        item[kSecAttrAccess as String] = access
    }

    private func debugBuildAccessAlreadyPermitsAnyApp(account: String) -> Bool {
        var query = baseQuery(account: account)
        query[kSecReturnRef as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        // A CFTypeRef downcast to a CoreFoundation type always succeeds, so check
        // the type ID explicitly rather than letting `as?` vouch for it.
        guard status == errSecSuccess,
              let item,
              CFGetTypeID(item) == SecKeychainItemGetTypeID() else { return false }
        let keychainItem = unsafeDowncast(item, to: SecKeychainItem.self)

        var access: SecAccess?
        guard SecKeychainItemCopyAccess(keychainItem, &access) == errSecSuccess,
              let access,
              let decryptACLs = SecAccessCopyMatchingACLList(access, kSecACLAuthorizationDecrypt) as? [SecACL] else {
            return false
        }

        return decryptACLs.contains { acl in
            var applicationList: CFArray?
            var description: CFString?
            var promptSelector = SecKeychainPromptSelector()
            let status = SecACLCopyContents(acl, &applicationList, &description, &promptSelector)
            return status == errSecSuccess && applicationList == nil
        }
    }

    private func makeDebugBuildAccess(account: String) -> SecAccess? {
        let descriptor = "\(service):\(account)" as CFString
        var access: SecAccess?
        let status = SecAccessCreate(descriptor, [] as CFArray, &access)
        guard status == errSecSuccess, let access else {
            logger.error(
                "SecAccessCreate failed for account '\(account, privacy: .public)' (OSStatus \(status))"
            )
            return nil
        }

        guard let decryptACLs = SecAccessCopyMatchingACLList(access, kSecACLAuthorizationDecrypt) as? [SecACL] else {
            logger.error("SecAccessCopyMatchingACLList failed for account '\(account, privacy: .public)'")
            return nil
        }

        // Debug builds change code signatures often; make only secret reads independent
        // of the current rebuilt binary while leaving release items on the system default.
        for acl in decryptACLs {
            let setStatus = SecACLSetContents(acl, nil, descriptor, SecKeychainPromptSelector())
            if setStatus != errSecSuccess {
                logger.error(
                    "SecACLSetContents failed for account '\(account, privacy: .public)' (OSStatus \(setStatus))"
                )
                return nil
            }
        }

        return access
    }
    #else
    private func refreshDebugBuildAccessIfNeeded(account: String) {}

    private func applyDebugBuildAccess(to item: inout [String: Any], account: String) {}
    #endif
}
