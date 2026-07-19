//
//  Accounts+SyncedSnapshot.swift
//  coderpad
//

import Foundation

extension Keychain {
    struct SyncedAccountsSnapshot: Codable, Equatable {
        let accounts: Data
        let revision: Data
    }

    static func encodeSyncedAccountsSnapshot(accounts: Data, revision: Data) -> Data? {
        try? accountEncoder.encode(SyncedAccountsSnapshot(accounts: accounts, revision: revision))
    }

    static func decodeSyncedAccountsSnapshot(_ data: Data) -> SyncedAccountsSnapshot? {
        guard let snapshot = try? accountDecoder.decode(SyncedAccountsSnapshot.self, from: data),
              normalizedRevisionData(snapshot.revision) != nil else { return nil }

        return snapshot
    }

    /// Reads the atomic v2 item first. A legacy snapshot is accepted over it only when
    /// its revision is strictly newer, which lets an older app publish a completed edit
    /// without treating a half-written equal-revision pair as a transaction (#2854).
    static func readSyncedAccountsSnapshot() -> SyncedAccountsSnapshot? {
        let atomic = readSynchronizableData(account: syncedAccountsSnapshotAccount)
            .flatMap(decodeSyncedAccountsSnapshot)
        let legacy = readSynchronizableData(account: accountsAccount).map { accounts in
            let revision = normalizedRevisionData(readSynchronizableData(account: accountsRevisionAccount))
                ?? nextRevisionData([])
            return SyncedAccountsSnapshot(accounts: accounts, revision: revision)
        }

        return newestSyncedSnapshot(atomic: atomic, legacy: legacy)
    }

    static func newestSyncedSnapshot(atomic: SyncedAccountsSnapshot?,
                                     legacy: SyncedAccountsSnapshot?) -> SyncedAccountsSnapshot? {
        guard let atomic else { return legacy }
        guard let legacy else { return atomic }

        return revision(from: legacy.revision) > revision(from: atomic.revision) ? legacy : atomic
    }
}
