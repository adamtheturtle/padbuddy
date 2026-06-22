//
//  CloudSync.swift
//  coderpad
//
//  iCloud sync foundation (#536): a stable cross-device account identity, the pure
//  merge helpers that move per-account collections between their local (UUID-keyed)
//  and cloud (sync-id-keyed) forms, and a thin best-effort mirror over iCloud's
//  key-value store.
//
//  Design notes:
//  - UserDefaults stays the source of truth for the running app. `CloudSyncStore`
//    only pushes a copy up and pulls external changes down, so when iCloud is
//    unavailable every method is a no-op and behaviour is exactly as before.
//  - iCloud's key-value store needs the profile-gated `ubiquity-kvstore-identifier`
//    entitlement, which the unprovisioned Developer ID build can't carry (the same
//    family of entitlement that broke launch as keychain-access-groups did). So on
//    the Developer ID build `isAvailable` is false and none of this runs; the App
//    Store target is where it lights up, once its iCloud container is registered.
//  - Credentials NEVER pass through here. The accounts array stays in the Keychain,
//    which has its own opt-in iCloud Keychain sync.
//

import Foundation
import Security

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

// MARK: - Pure merge helpers

/// Cross-device merge helpers for the per-account favourite / saved-search / template
/// blobs (#536). Kept as pure functions so the merge semantics are unit-testable
/// without iCloud; ``CloudSyncStore`` only orchestrates I/O around them.
enum AccountSyncMerge {
    /// Projects a local, per-`UUID` blob into its cloud form keyed by stable sync id,
    /// dropping accounts whose sync id is empty (drafts) or that `syncID` can't
    /// resolve. When two local accounts share a sync id (shouldn't happen for a real
    /// org key) the last one wins, which is harmless for a mirror.
    static func toCloud<Value>(_ local: [UUID: Value], syncID: (UUID) -> String?) -> [String: Value] {
        var cloud: [String: Value] = [:]
        for (uuid, value) in local {
            guard let identity = syncID(uuid), !identity.isEmpty else { continue }

            cloud[identity] = value
        }
        return cloud
    }

    /// Merges a cloud blob (keyed by sync id) back into a local one (keyed by `UUID`),
    /// additively per account: each array is unioned with local order preserved and
    /// cloud-only elements appended, so neither device's pins are lost. Deletions do
    /// NOT propagate in v1 - a safe-by-default choice while element-level merge is out
    /// of scope (a removal on one Mac won't wipe the pin on another). `uuidForSyncID`
    /// resolves a stable id back to a configured local account; cloud entries for
    /// accounts not present on this device are ignored.
    static func mergeArrays<Element: Equatable>(
        cloud: [String: [Element]],
        into local: [UUID: [Element]],
        uuidForSyncID: (String) -> UUID?
    ) -> [UUID: [Element]] {
        var merged = local
        for (identity, cloudList) in cloud {
            guard let uuid = uuidForSyncID(identity) else { continue }

            var list = merged[uuid] ?? []
            for element in cloudList where !list.contains(element) {
                list.append(element)
            }
            merged[uuid] = list
        }
        return merged
    }

    /// Like ``mergeArrays`` but unions each account's array by a stable element `id`
    /// rather than by full-value equality, so the same logical item is never
    /// duplicated when a mutable field differs between devices — e.g. a favourite
    /// question whose captured title was backfilled on one Mac but not the other, or a
    /// saved search the user renamed. The local entry wins for ids present on both
    /// sides (it isn't overwritten); cloud-only items are appended, preserving local
    /// order. Deletions don't propagate in v1, matching ``mergeArrays`` (#536).
    static func mergeArrays<Element>(
        cloud: [String: [Element]],
        into local: [UUID: [Element]],
        uuidForSyncID: (String) -> UUID?,
        id: (Element) -> AnyHashable
    ) -> [UUID: [Element]] {
        var merged = local
        for (identity, cloudList) in cloud {
            guard let uuid = uuidForSyncID(identity) else { continue }

            var list = merged[uuid] ?? []
            var present = Set(list.map(id))
            for element in cloudList where present.insert(id(element)).inserted {
                list.append(element)
            }
            merged[uuid] = list
        }
        return merged
    }

    /// The nested counterpart of the id-keyed ``mergeArrays``, for collections that are
    /// partitioned by an inner string key before the array — saved searches, which are
    /// kept per account *and* per list kind (`pads`/`questions`). Unions each
    /// (account, kind) bucket by element `id` with the same v1 semantics (#536).
    static func mergeNestedArrays<Element>(
        cloud: [String: [String: [Element]]],
        into local: [UUID: [String: [Element]]],
        uuidForSyncID: (String) -> UUID?,
        id: (Element) -> AnyHashable
    ) -> [UUID: [String: [Element]]] {
        var merged = local
        for (identity, cloudBuckets) in cloud {
            guard let uuid = uuidForSyncID(identity) else { continue }

            var buckets = merged[uuid] ?? [:]
            for (bucketKey, cloudList) in cloudBuckets {
                var list = buckets[bucketKey] ?? []
                var present = Set(list.map(id))
                for element in cloudList where present.insert(id(element)).inserted {
                    list.append(element)
                }
                buckets[bucketKey] = list
            }
            merged[uuid] = buckets
        }
        return merged
    }
}

// MARK: - Best-effort iCloud mirror

/// A thin, best-effort mirror of small per-account collections into iCloud's
/// key-value store (#536). A no-op whenever iCloud is unavailable, so the call sites
/// stay oblivious to iCloud and the Developer ID build is unaffected.
@MainActor
final class CloudSyncStore {
    static let shared = CloudSyncStore()

    /// Posted after an external iCloud change has arrived, with the changed cloud key
    /// in `userInfo["key"]`, so the owning store can re-pull and merge.
    static let didChangeExternally = Notification.Name("CloudSyncStore.didChangeExternally")

    private var observer: (any NSObjectProtocol)?

    private init() {}

    /// The shared iCloud KVS, accessed lazily and ONLY behind ``isAvailable`` — merely
    /// referencing `NSUbiquitousKeyValueStore.default` without the ubiquity entitlement
    /// logs "BUG IN CLIENT OF KVS: …", so it must never be touched on an unentitled build.
    private var store: NSUbiquitousKeyValueStore {
        .default
    }

    /// Whether the app actually carries the `ubiquity-kvstore-identifier` entitlement.
    /// Checked once via the code signature: being signed into iCloud is NOT enough
    /// (`ubiquityIdentityToken` is non-nil whenever iCloud is on, entitlement or not), so
    /// this is the gate that keeps KVS untouched on the unprovisioned Developer ID build.
    private static let hasUbiquityEntitlement: Bool = {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }

        let key = "com.apple.developer.ubiquity-kvstore-identifier" as CFString
        return SecTaskCopyValueForEntitlement(task, key, nil) != nil
    }()

    /// True only when iCloud is genuinely usable: the app is provisioned with the KVS
    /// entitlement AND the user is signed into iCloud. Correctly false on the
    /// unprovisioned Developer ID build, so the KVS is never initialized there.
    var isAvailable: Bool {
        Self.hasUbiquityEntitlement && FileManager.default.ubiquityIdentityToken != nil
    }

    /// Begins observing external iCloud changes and pulls the current cloud state.
    /// Idempotent; a no-op when iCloud is unavailable.
    func start() {
        guard isAvailable, observer == nil else { return }

        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { note in
            let keys = (note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]) ?? []
            // Delivered on the main queue, so we're already on the main actor.
            MainActor.assumeIsolated { Self.shared.broadcast(changedKeys: keys) }
        }
        store.synchronize()
    }

    /// Mirrors `data` to iCloud under `key`. No-op when iCloud is unavailable.
    func mirror(_ data: Data, forKey key: String) {
        guard isAvailable else { return }

        store.set(data, forKey: key)
    }

    /// The cloud copy of `key`, or `nil` when absent or iCloud is unavailable.
    func data(forKey key: String) -> Data? {
        guard isAvailable else { return nil }

        return store.data(forKey: key)
    }

    /// Mirrors a plist-type preference value (`String`/`Int`/`Bool`/`Data`/…) to iCloud,
    /// or clears it when `value` is nil. Used by ``PreferenceCloudSync`` for the plain
    /// app-global settings the Settings window writes (#536). No-op when unavailable.
    func mirrorObject(_ value: Any?, forKey key: String) {
        guard isAvailable else { return }

        if let value {
            store.set(value, forKey: key)
        } else {
            store.removeObject(forKey: key)
        }
    }

    /// The cloud copy of a plist-type preference value, or `nil` when absent or iCloud
    /// is unavailable.
    func object(forKey key: String) -> Any? {
        guard isAvailable else { return nil }

        return store.object(forKey: key)
    }

    private func broadcast(changedKeys: [String]) {
        for key in changedKeys {
            NotificationCenter.default.post(
                name: Self.didChangeExternally, object: nil, userInfo: ["key": key]
            )
        }
    }
}
