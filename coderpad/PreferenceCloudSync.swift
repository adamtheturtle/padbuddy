//
//  PreferenceCloudSync.swift
//  coderpad
//
//  iCloud sync for the plain app-global preferences (#536). The per-account
//  collections (favourites) ride their own stores' sync-id-keyed mirrors; this
//  handles the flat scalar UserDefaults the Settings
//  window writes - appearance, sort order, browser choice, and so on.
//
//  Model: last-writer-wins per key. For a single user's preferences that's the right
//  behaviour - the most recent change on any Mac becomes the truth everywhere. The
//  loop that would otherwise form (cloud change -> write UserDefaults -> local-change
//  notification -> push back to cloud) is broken by VALUE, not timing: every push and
//  pull first checks the two sides already differ, so applying a pulled value makes
//  the subsequent push a no-op and the system converges.
//
//  A no-op whenever iCloud is unavailable, so the Developer ID build (which can't carry
//  the ubiquity entitlement) behaves exactly as before. Credentials deliberately stay
//  out of this KVS mirror; saved accounts use the system iCloud Keychain path instead
//  (#678). Device-local choices such as launch-at-login are also excluded.
//

import Foundation

@MainActor
final class PreferenceCloudSync {
    static let shared = PreferenceCloudSync()

    /// The UserDefaults keys that sync, gathered here so the policy is auditable in one
    /// place against the #536 inventory. Anything not listed stays device-local - most
    /// importantly credentials (handled by iCloud Keychain, not KVS) and window/UI state.
    static let syncedKeys: [String] = [
        // Continuity preferences.
        "pads.sort",
        "questions.sort",
        "pads.merged.liveFilter",
        "questions.merged.liveFilter",
        // App-global settings.
        "general.appearance",
        "general.presence",
        "general.dockBadgeScope",
        "general.spotlightIndexing",
        "general.notifyOnPadUpdates",
        "browser.defaultBrowserBundleID",
        "browser.openInBackground"
    ]

    private var defaultsObserver: (any NSObjectProtocol)?
    private var cloudObserver: (any NSObjectProtocol)?

    private init() {}

    /// Adopts the cloud's preference values, then begins mirroring local changes up and
    /// pulling external changes down. Idempotent; a no-op when iCloud is unavailable.
    func start() {
        guard CloudSyncStore.shared.isAvailable, defaultsObserver == nil else { return }

        // Adopt any cloud values on launch before we start mirroring, so a fresh Mac
        // inherits the user's settings instead of pushing its defaults over them.
        for key in Self.syncedKeys {
            pull(key: key)
        }

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: UserDefaults.standard, queue: .main
        ) { _ in
            // Delivered on the posting (main) thread for the standard defaults.
            MainActor.assumeIsolated { Self.shared.mirrorChangedToCloud() }
        }
        cloudObserver = NotificationCenter.default.addObserver(
            forName: CloudSyncStore.didChangeExternally, object: nil, queue: .main
        ) { note in
            let key = note.userInfo?["key"] as? String
            MainActor.assumeIsolated {
                guard let key, Self.syncedKeys.contains(key) else { return }

                Self.shared.pull(key: key)
            }
        }
    }

    /// Pushes any synced key whose local value differs from the cloud copy. Cheap enough
    /// to run on every defaults change: the list is short and KVS reads are in-memory.
    private func mirrorChangedToCloud() {
        for key in Self.syncedKeys {
            let local = UserDefaults.standard.object(forKey: key)
            let cloud = CloudSyncStore.shared.object(forKey: key)
            guard !Self.plistValuesEqual(local, cloud) else { continue }

            CloudSyncStore.shared.mirrorObject(local, forKey: key)
        }
    }

    /// Pulls one key's cloud value into UserDefaults when it differs. A missing cloud
    /// value never clears a local one (deletions don't propagate, matching the
    /// collection stores). Writing the value re-posts `didChangeNotification`, but the
    /// resulting push is a no-op because the two sides now match - this is what makes
    /// the sync converge instead of looping.
    private func pull(key: String) {
        guard let cloud = CloudSyncStore.shared.object(forKey: key) else { return }

        let local = UserDefaults.standard.object(forKey: key)
        guard !Self.plistValuesEqual(local, cloud) else { return }

        UserDefaults.standard.set(cloud, forKey: key)
    }

    /// Whether two plist-type preference values are equal, treating two absent values as
    /// equal. UserDefaults and KVS hand back Foundation objects (`NSString`/`NSNumber`/
    /// `NSData`/…) whose `isEqual:` is the correct value comparison; pulled together here
    /// (and made `static`) so the convergence rule is unit-testable without iCloud.
    static func plistValuesEqual(_ lhs: Any?, _ rhs: Any?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            true
        case let (lhs?, rhs?):
            (lhs as? NSObject)?.isEqual(rhs as? NSObject) ?? false
        default:
            false
        }
    }
}
