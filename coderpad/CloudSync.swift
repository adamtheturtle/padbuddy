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
import CryptoKit
import Foundation

// MARK: - Stable cross-device identity

extension Account {
    /// A stable identity that is identical across a user's devices, for keying
    /// iCloud-synced data (#536). The local ``id`` is a per-device random `UUID`, so
    /// it can't line up between Macs; the normalized endpoint, owner email, and API-key
    /// fingerprint do. Case-folded so trivial email differences don't fork the key.
    /// Empty for an in-progress draft with no owner email or key yet, which the sync
    /// layer skips.
    var syncID: String {
        let email = userEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !email.isEmpty else { return "" }

        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return "" }

        return "\(syncEndpointID)|\(email)|\(Self.apiKeyFingerprint(key))"
    }

    private var syncEndpointID: String {
        let url = resolvedBaseURL
        let scheme = url.scheme?.lowercased() ?? "https"
        let host = url.host?.lowercased() ?? ""
        let port = url.port.map { ":\($0)" } ?? ""
        let path = normalizedSyncPath(url.path)
        return "\(scheme)://\(host)\(port)\(path)"
    }

    private func normalizedSyncPath(_ rawPath: String) -> String {
        var path = rawPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !path.isEmpty else { return "" }

        path = path
            .split(separator: "/", omittingEmptySubsequences: true)
            .joined(separator: "/")
        return "/\(path)"
    }

    private static func apiKeyFingerprint(_ key: String) -> String {
        SHA256.hash(data: Data(key.utf8))
            .prefix(12)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
