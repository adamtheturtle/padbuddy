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
/// fresh key for the same pad each time (#4546).
///
/// A claim carries a process-unique token rather than a per-key counter. With a counter,
/// an entry that was dropped and recreated restarted at 1, so a claim from before the drop
/// compared equal to the new one and looked current again. A token is never reused, so a
/// recreated entry can never revive a stale claim however the entry came and went.
nonisolated struct PadMutationRevisionStore {
    struct Key: Hashable {
        let accountID: UUID?
        let padID: String
        let clientIdentity: ClientTaskIdentity
    }

    struct Claim: Equatable {
        let key: Key
        let token: UInt64
    }

    /// The token whose holder currently owns each key.
    private var tokens: [Key: UInt64] = [:]
    /// How many claims are outstanding per key, so a key is dropped only once the last
    /// mutation using it has settled.
    private var outstanding: [Key: Int] = [:]
    private var nextToken: UInt64 = 0

    var trackedKeyCount: Int {
        tokens.count
    }

    mutating func claim(_ key: Key) -> Claim {
        nextToken &+= 1
        tokens[key] = nextToken
        outstanding[key, default: 0] += 1
        return Claim(key: key, token: nextToken)
    }

    mutating func invalidate(_ key: Key) {
        // Nothing is waiting on this key, so there is no claim to defeat and the entry is
        // only bookkeeping. Dropping it keeps a deleted pad from being retained.
        guard outstanding[key, default: 0] > 0 else {
            tokens[key] = nil
            return
        }

        nextToken &+= 1
        tokens[key] = nextToken
    }

    func isCurrent(_ claim: Claim) -> Bool {
        tokens[claim.key] == claim.token
    }

    /// Marks a claim's mutation as settled. Call this once per ``claim(_:)``, whatever the
    /// outcome, so the entry can be dropped when the last in-flight mutation for that pad
    /// finishes.
    mutating func release(_ claim: Claim) {
        let remaining = (outstanding[claim.key] ?? 0) - 1
        guard remaining > 0 else {
            outstanding[claim.key] = nil
            tokens[claim.key] = nil
            return
        }

        outstanding[claim.key] = remaining
    }

    /// Drops every key belonging to an account, for use when the account is removed or
    /// re-keyed. Outstanding claims for those keys stop being current, which is what a
    /// removed account should mean for a mutation still in flight against it.
    mutating func removeAll(accountID: UUID) {
        for key in tokens.keys where key.accountID == accountID {
            tokens[key] = nil
            outstanding[key] = nil
        }
    }

    /// Drops every key belonging to a client identity, for use when credentials rotate and
    /// the old client's keys can never be claimed again.
    mutating func removeAll(clientIdentity: ClientTaskIdentity) {
        for key in tokens.keys where key.clientIdentity == clientIdentity {
            tokens[key] = nil
            outstanding[key] = nil
        }
    }
}
