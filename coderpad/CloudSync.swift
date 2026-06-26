//
//  CloudSync.swift
//  coderpad
//
//  iCloud sync foundation (#536): a stable cross-device account identity. The pure
//  merge strategies (`CloudSyncMerge`) and the iCloud key-value mirror (`CloudSyncStore`)
//  now live in buddy-kit's BuddyAppKit; this file keeps only the CoderPad-specific
//  `Account.syncID` derivation that keys them.
//

import BuddyAppKit
import Foundation

// MARK: - Stable cross-device identity

extension Account {
    /// A stable identity that is identical across a user's devices, for keying
    /// iCloud-synced data (#536). The local ``id`` is a per-device random `UUID`, so
    /// it can't line up between Macs; the resolved server host plus the owner email
    /// do - both are the same wherever the same org key is configured. Case-folded so
    /// trivial differences don't fork the key. Empty for an in-progress draft with no
    /// owner email yet, which the sync layer skips.
    var syncID: String {
        let email = userEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !email.isEmpty else { return "" }

        let host = resolvedBaseURL.host?.lowercased() ?? ""
        return "\(host)|\(email)"
    }
}
