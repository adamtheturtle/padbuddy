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

extension AccountsStore {
    /// A `[UUID: String]` index of every account's cross-device sync id.
    ///
    /// The mirror closures resolved each account by scanning `accounts` for a
    /// matching id, once per account being mirrored — O(accounts²) on the save path,
    /// which several stores hit on every mutation (#2439). Empty sync ids (a draft
    /// with no key or owner yet) are omitted, so a lookup still yields nil for them.
    @MainActor
    var syncIDsByAccountID: [UUID: String] {
        var index: [UUID: String] = [:]
        for account in accounts where !account.syncID.isEmpty {
            index[account.id] = account.syncID
        }
        return index
    }
}

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
        title: WritableKeyPath<Element, String>
    ) -> [UUID: [Element]] {
        var result = merged
        for (identity, cloudList) in cloud {
            guard let uuid = uuidForSyncID(identity), var list = result[uuid] else { continue }

            let cloudTitles = Dictionary(cloudList.map { (id($0), $0[keyPath: title]) },
                                         uniquingKeysWith: { first, _ in first })
            var changed = false
            for index in list.indices {
                guard let cloudTitle = cloudTitles[id(list[index])],
                      !cloudTitle.isEmpty, cloudTitle != list[index][keyPath: title] else { continue }

                list[index][keyPath: title] = cloudTitle
                changed = true
            }
            if changed { result[uuid] = list }
        }
        return result
    }
}

// MARK: - Deletion tombstones (#738, #723)

/// Cross-device deletion semantics for the additively-merged per-account blobs.
/// `CloudSyncMerge.mergeArrays`/`mergeTimestamps` deliberately never delete, so a
/// favorite removed on one Mac was unioned back by another device's mirror and
/// could resurrect everywhere (#738); the same held for a deleted pad's
/// open-history timestamp (#723). Each store now records a dated tombstone when
/// it removes an entry, mirrors the tombstones alongside the items, and resolves
/// the two after every merge: the newer side wins, so a removal beats the entry
/// it removed while a later re-add beats the tombstone.
nonisolated enum CloudTombstones {
    /// How long a tombstone is kept before it's pruned. Any device that syncs
    /// within this window converges; after it, the entry is long gone from every
    /// mirror, so the tombstone no longer earns its storage.
    static let retention: TimeInterval = 60 * 60 * 24 * 60

    /// Resolves favorite-style items (carrying an optional `addedAt`) against
    /// tombstones: an item whose tombstone is newer than its `addedAt` is dropped
    /// (removed elsewhere); an item re-added after the tombstone survives and
    /// retires the tombstone. Items persisted before `addedAt` existed count as
    /// arbitrarily old, so a tombstone always beats them.
    static func resolve<Element>(
        items: [Element],
        tombstones: [String: Date],
        id: (Element) -> String,
        addedAt: (Element) -> Date?
    ) -> (items: [Element], tombstones: [String: Date]) {
        var liveTombstones = tombstones
        let kept = items.filter { item in
            guard let removedAt = tombstones[id(item)] else { return true }

            if (addedAt(item) ?? .distantPast) > removedAt {
                liveTombstones[id(item)] = nil
                return true
            }
            return false
        }
        return (kept, liveTombstones)
    }

    /// The open-history variant, where the entry's own date is the recency signal:
    /// an entry older than its tombstone is dropped; a newer one (the pad was
    /// opened again after the deletion) retires the tombstone.
    static func resolveTimestamps(
        entries: [String: Date],
        tombstones: [String: Date]
    ) -> (entries: [String: Date], tombstones: [String: Date]) {
        var liveTombstones = tombstones
        let kept = entries.filter { key, opened in
            guard let removedAt = tombstones[key] else { return true }

            if opened > removedAt {
                liveTombstones[key] = nil
                return true
            }
            return false
        }
        return (kept, liveTombstones)
    }

    /// Tombstones older than ``retention``, dropped so the maps stay bounded.
    static func pruned(_ tombstones: [String: Date], now: Date = Date()) -> [String: Date] {
        tombstones.filter { now.timeIntervalSince($0.value) < retention }
    }
}
