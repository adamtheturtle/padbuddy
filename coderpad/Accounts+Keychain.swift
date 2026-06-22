//
//  Accounts+Keychain.swift
//  coderpad
//
//  Keychain access for multi-account key storage.
//

import Foundation

/// App-side facade over ``KeychainStore`` (in BuddyAppKit), pinning the service name.
/// The implementation lives in the package so a sibling app can reuse it with its own
/// service; this layer keeps the call sites unchanged and, crucially, holds the
/// `com.coderpad.app` service string **byte-for-byte** — change it and every existing
/// user loses their saved accounts (the items are keyed by it). See KeychainStore for
/// the legacy- vs data-protection-keychain rationale (#451/#460).
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
}
