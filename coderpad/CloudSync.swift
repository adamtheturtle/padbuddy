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
    /// it can't line up between Macs; the normalized endpoint and owner email do.
    /// The API key is deliberately only an eligibility check, not identity: rotating
    /// credentials must not strand the account's cloud state under the old key (#2141).
    /// Case-folded so trivial email differences don't fork the key.
    /// Empty for an in-progress draft with no owner email or key yet, which the sync
    /// layer skips.
    var syncID: String {
        let email = userEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !email.isEmpty else { return "" }

        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return "" }

        return "\(syncEndpointID)|\(email)"
    }

    private var syncEndpointID: String {
        let url = resolvedBaseURL
        let scheme = url.scheme?.lowercased() ?? "https"
        let host = url.host?.lowercased() ?? ""
        let port = url.port.map { ":\($0)" } ?? ""
        let path = normalizedSyncPath(url.path)
        return "\(scheme)://\(host)\(port)\(path)"
    }

    /// Collapses a base-URL path to one canonical spelling. Repeated slashes are
    /// dropped, and `.`/`..` segments are resolved (#2142): `/api/../api` and `/api`
    /// address the same server, so leaving them distinct forked the account's cloud
    /// state into two identities that never converged. A `..` that would climb above
    /// the root is discarded, matching how a server resolves it.
    private func normalizedSyncPath(_ rawPath: String) -> String {
        var segments: [Substring] = []
        for segment in rawPath.split(separator: "/", omittingEmptySubsequences: true) {
            switch segment {
            case ".": continue
            case "..": if !segments.isEmpty { segments.removeLast() }
            default: segments.append(segment)
            }
        }
        guard !segments.isEmpty else { return "" }

        return "/\(segments.joined(separator: "/"))"
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

            // Duplicate cloud rows for one id are collapsed to the longest usable
            // title rather than whichever happened to come first in the array, so two
            // devices reading the same blob adopt the same title instead of
            // disagreeing on incidental order (#2145). Length is the tie-break because
            // a truncated or placeholder title is the usual cause of a duplicate;
            // equal-length titles fall back to sort order, which is still stable.
            let cloudTitles = Dictionary(
                cloudList.map { (id($0), $0[keyPath: title]) },
                uniquingKeysWith: { first, second in
                    let left = first.trimmingCharacters(in: .whitespacesAndNewlines)
                    let right = second.trimmingCharacters(in: .whitespacesAndNewlines)
                    if left.isEmpty { return second }
                    if right.isEmpty { return first }
                    if left.count != right.count { return left.count > right.count ? first : second }

                    return left <= right ? first : second
                }
            )
            var changed = false
            for index in list.indices {
                guard let cloudTitle = cloudTitles[id(list[index])] else { continue }

                let incoming = cloudTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                let existing = list[index][keyPath: title].trimmingCharacters(in: .whitespacesAndNewlines)
                // Compared trimmed and case-insensitively: a title differing only in
                // whitespace or casing is the same title, and adopting it wrote a new
                // value that the other device then mirrored back, churning on every
                // sync (#2146).
                guard !incoming.isEmpty,
                      incoming.compare(existing, options: [.caseInsensitive]) != .orderedSame else { continue }

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
        // Survivors are de-duplicated by id as well as filtered: the merge that feeds
        // this is an additive union, so the same favourite can arrive from two devices
        // and both copies stayed visible and re-propagated (#2147).
        var seenIDs = Set<String>()
        let kept = items.filter { item in
            guard seenIDs.insert(id(item)).inserted else { return false }
            guard let removedAt = tombstones[id(item)] else { return true }

            // `>=`, not `>`: a re-add recorded in the same instant as the removal is a
            // real re-add, and strict comparison made it lose to the tombstone and
            // vanish indefinitely (#2148). Timestamps here come from separate devices
            // with second-or-worse effective resolution, so equal values are common.
            // Items persisted before `addedAt` existed still lose, since `.distantPast`
            // is never equal to a real removal date.
            if (addedAt(item) ?? .distantPast) >= removedAt {
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

            // `>=` for the same reason as `resolve` above (#2148).
            if opened >= removedAt {
                liveTombstones[key] = nil
                return true
            }
            return false
        }
        return (kept, liveTombstones)
    }

    /// The most tombstones kept for one key space.
    ///
    /// Retention alone let the maps grow with every removal for sixty days, so
    /// automated favourite or open-history churn could build a KVS payload large
    /// enough to fail to sync — taking the rest of the mirror down with it (#2150).
    static let maxTombstones = 500

    /// Tombstones worth keeping: recent enough to still matter, and bounded in number.
    ///
    /// A future-dated tombstone has a negative age, so an `age < retention` test kept
    /// it forever and a device with a bad clock could suppress an item permanently
    /// (#2149). Anything dated beyond a small tolerance into the future is treated as
    /// unusable and dropped. When still over the cap, the newest are kept: an old
    /// tombstone is the one most likely to have already converged everywhere.
    static func pruned(_ tombstones: [String: Date], now: Date = Date()) -> [String: Date] {
        let live = tombstones.filter { _, removedAt in
            let age = now.timeIntervalSince(removedAt)
            return age < retention && age > -futureTolerance
        }
        guard live.count > maxTombstones else { return live }

        return Dictionary(uniqueKeysWithValues: live
            .sorted { $0.value > $1.value }
            .prefix(maxTombstones)
            .map { ($0.key, $0.value) })
    }

    /// How far ahead of this device's clock a tombstone may be dated and still count.
    /// Devices disagree by seconds routinely; a tombstone dated further ahead than
    /// this came from a misconfigured clock (#2149).
    private static let futureTolerance: TimeInterval = 60 * 60
}
