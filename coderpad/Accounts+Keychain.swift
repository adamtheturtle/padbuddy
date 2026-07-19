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
    /// Shared coders for the accounts snapshot.
    ///
    /// The store's config closures allocated a fresh `JSONEncoder`/`JSONDecoder` on
    /// every save and load, and the iCloud mirror allocated another — all of which run
    /// again on each add, remove, rename, and current-account switch (#2446).
    /// `JSONEncoder`/`JSONDecoder` are value-semantic and stateless once configured,
    /// so one of each is safe to share.
    static let accountEncoder = JSONEncoder()
    static let accountDecoder = JSONDecoder()

    static let service = "com.coderpad.app"
    static let accountsAccount = "accounts"
    /// A wall-clock revision stamp written alongside each accounts snapshot (locally
    /// and in iCloud Keychain), so reconciliation can tell which side is newer instead
    /// of letting a stale cloud copy unconditionally win (#768).
    static let accountsRevisionAccount = "accountsRevision"
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

    /// Whether the local accounts snapshot is *definitively absent*: the probe
    /// completed and reported `errSecItemNotFound`. Any other failure (locked,
    /// denied, interaction not allowed) means secure storage is unavailable —
    /// which must not be mistaken for "no accounts", or legacy migration and
    /// empty UI state would run over the user's real snapshot (#1157).
    static func accountsSnapshotIsDefinitivelyAbsent() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountsAccount,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status != errSecSuccess, status != errSecItemNotFound {
            persistenceLogger.error(
                "Keychain accounts probe failed (OSStatus \(status)); treating storage as unavailable."
            )
        }
        return status == errSecItemNotFound
    }

    /// Reconciles the existing local account blob with the user's iCloud Keychain copy
    /// before `AccountsStore` loads. A fresh device adopts the synced snapshot and a
    /// local-only install seeds iCloud Keychain once - but the cloud copy only replaces
    /// a differing local one when it actually decodes to usable accounts (#769) AND its
    /// revision stamp is newer (#768); otherwise the local snapshot wins and is pushed
    /// back up, so a malformed or stale synced blob can't wipe or revert local accounts.
    @MainActor
    static func reconcileSyncedAccounts() {
        let local = readData(account: accountsAccount)
        let synced = readSynchronizableData(account: accountsAccount)

        switch (local, synced) {
        case (nil, nil):
            return

        case let (local?, nil):
            // A local-only install seeds iCloud Keychain once.
            mirrorAccountsToiCloudKeychain(local)

        case let (nil, synced?):
            // A fresh device adopts the synced snapshot - when it decodes (#769).
            guard decodesToUsableAccounts(synced) else {
                persistenceLogger.error("iCloud Keychain accounts blob doesn't decode; not adopting it.")
                return
            }

            write(synced, account: accountsAccount)
            if let cloudRevision = readSynchronizableData(account: accountsRevisionAccount) {
                write(cloudRevision, account: accountsRevisionAccount)
            }

        case let (local?, synced?):
            guard local != synced else { return }
            guard decodesToUsableAccounts(synced) else {
                // Malformed or schema-incompatible cloud bytes must never replace a
                // local snapshot: decoding them later yields [] and every local
                // account would disappear (#769). Keep local; leave the cloud item
                // for an app version that understands it.
                persistenceLogger.error("iCloud Keychain accounts blob doesn't decode; keeping the local snapshot.")
                return
            }

            let localRevision = revision(from: readData(account: accountsRevisionAccount))
            let cloudRevision = revision(from: readSynchronizableData(account: accountsRevisionAccount))
            if cloudRevision > localRevision {
                write(synced, account: accountsAccount)
                if let cloudRevisionData = readSynchronizableData(account: accountsRevisionAccount) {
                    write(cloudRevisionData, account: accountsRevisionAccount)
                }
            } else {
                // The local snapshot is as new or newer (e.g. an edit whose iCloud
                // mirror failed or lagged): local wins and refreshes the cloud copy,
                // instead of the stale cloud blob reverting the change (#768).
                mirrorAccountsToiCloudKeychain(local)
            }
        }
    }

    static func mirrorAccountsToiCloudKeychain(_ data: Data?) {
        guard let data else {
            deleteSynchronizable(account: accountsAccount)
            deleteSynchronizable(account: accountsRevisionAccount)
            delete(account: accountsRevisionAccount)
            return
        }

        // Stamp the snapshot's revision locally FIRST: if the iCloud writes below then
        // fail or lag, the local revision is newer than the stale cloud one and wins
        // the next launch's reconciliation (#768).
        let revision = revisionData(Date())
        write(revision, account: accountsRevisionAccount)
        writeSynchronizable(data, account: accountsAccount)
        writeSynchronizable(revision, account: accountsRevisionAccount)
    }

    /// Whether `data` decodes to at least one usable account or a genuinely empty
    /// list. Malformed JSON, or a future schema whose every element fails the lenient
    /// per-element decode, is not usable (#769).
    @MainActor
    private static func decodesToUsableAccounts(_ data: Data) -> Bool {
        guard let elements = try? JSONDecoder().decode([LenientElement<Account>].self, from: data) else {
            return false
        }

        return elements.isEmpty || elements.contains { $0.value != nil }
    }

    private static func revisionData(_ date: Date) -> Data {
        Data(String(date.timeIntervalSince1970).utf8)
    }

    /// Parses a revision stamp, treating a missing or unreadable one as 0 (older than
    /// any stamped snapshot) so pre-revision installs upgrade cleanly.
    private static func revision(from data: Data?) -> TimeInterval {
        guard let data, let text = String(bytes: data, encoding: .utf8),
              let value = TimeInterval(text) else { return 0 }

        return value
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
