//
//  CloudSync.swift
//  coderpad
//
//  iCloud sync foundation (#536): a stable cross-device account identity. The pure
//  merge strategies (`CloudSyncMerge`) and the iCloud key-value mirror (`CloudSyncStore`)
//  now live in buddy-kit's BuddyAppKit; this file keeps the CoderPad-specific
//  `Account.syncID` derivation that keys them, plus the favorite-title adoption
//  pass layered over the id-keyed union merge (#762).
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

// MARK: - Favorite title adoption (#762)

/// Adopts cloud-captured titles for favorites present on both sides of a sync.
/// The id-keyed `CloudSyncMerge.mergeArrays` union deliberately keeps the local
/// element when an id exists on both devices, so a favorite renamed on another
/// Mac kept its stale title here until this account's own list refresh backfilled
/// it (#762). Titles are server-derived (see the stores' `refreshTitles`), so
/// adopting a differing, non-empty cloud title is safe: any transient
/// disagreement between devices converges to the server's truth on the next
/// list load.
nonisolated enum FavoriteTitleSync {
    static func adoptCloudTitles<Element>(
        merged: [UUID: [Element]],
        cloud: [String: [Element]],
        uuidForSyncID: (String) -> UUID?,
        id: (Element) -> AnyHashable,
        title: (Element) -> String,
        setTitle: (inout Element, String) -> Void
    ) -> [UUID: [Element]] {
        var result = merged
        for (identity, cloudList) in cloud {
            guard let uuid = uuidForSyncID(identity), var list = result[uuid] else { continue }

            let cloudTitles = Dictionary(cloudList.map { (id($0), title($0)) },
                                         uniquingKeysWith: { first, _ in first })
            var changed = false
            for index in list.indices {
                guard let cloudTitle = cloudTitles[id(list[index])],
                      !cloudTitle.isEmpty, cloudTitle != title(list[index]) else { continue }

                setTitle(&list[index], cloudTitle)
                changed = true
            }
            if changed { result[uuid] = list }
        }
        return result
    }
}
