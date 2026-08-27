//
//  PadMutationRevisionStore.swift
//  coderpad
//

import Foundation

/// Revision counters that let a pad mutation notice its result is no longer wanted —
/// because a newer mutation for the same pad started, or because the pad was deleted
/// underneath it.
///
/// Entries exist only while a mutation is in flight. Keeping one per pad/client ever
/// touched grew this state for the life of the process, and a client rotation minted a
/// fresh key for the same pad each time (#4546). Releasing a settled claim is only safe
/// once nothing else holds a claim on that key: an entry that vanished and was recreated
/// would restart at revision 1 and make a stale outstanding claim look current again, so
/// the outstanding count decides when a key can go.
nonisolated struct PadMutationRevisionStore {
    struct Key: Hashable {
        let accountID: UUID?
        let padID: String
        let clientIdentity: ClientTaskIdentity
    }

    struct Claim: Equatable {
        let key: Key
        let revision: Int
    }

    private var revisions: [Key: Int] = [:]
    private var outstanding: [Key: Int] = [:]

    var trackedKeyCount: Int {
        revisions.count
    }

    mutating func claim(_ key: Key) -> Claim {
        revisions[key, default: 0] &+= 1
        outstanding[key, default: 0] += 1
        return Claim(key: key, revision: revisions[key, default: 0])
    }

    mutating func invalidate(_ key: Key) {
        revisions[key, default: 0] &+= 1
        // Nothing is waiting on this key, so the bump has no one to defeat and the entry
        // is only bookkeeping. Dropping it keeps a deleted pad from being retained.
        if outstanding[key, default: 0] == 0 {
            revisions[key] = nil
        }
    }

    func isCurrent(_ claim: Claim) -> Bool {
        revisions[claim.key] == claim.revision
    }

    /// Marks a claim's mutation as settled. Call this once per ``claim(_:)``, whatever the
    /// outcome, so the entry can be dropped when the last in-flight mutation for that pad
    /// finishes.
    mutating func release(_ claim: Claim) {
        let remaining = (outstanding[claim.key] ?? 0) - 1
        guard remaining > 0 else {
            outstanding[claim.key] = nil
            revisions[claim.key] = nil
            return
        }

        outstanding[claim.key] = remaining
    }

    /// Drops every key belonging to an account, for use when the account is removed or
    /// re-keyed. Outstanding claims for those keys stop being current, which is what a
    /// removed account should mean for a mutation still in flight against it.
    mutating func removeAll(accountID: UUID) {
        for key in revisions.keys where key.accountID == accountID {
            revisions[key] = nil
            outstanding[key] = nil
        }
    }

    /// Drops every key belonging to a client identity, for use when credentials rotate and
    /// the old client's keys can never be claimed again.
    mutating func removeAll(clientIdentity: ClientTaskIdentity) {
        for key in revisions.keys where key.clientIdentity == clientIdentity {
            revisions[key] = nil
            outstanding[key] = nil
        }
    }
}
