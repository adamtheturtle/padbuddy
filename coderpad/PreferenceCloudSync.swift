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

    /// Pushes any synced key whose local value differs from the cloud copy, stamping a
    /// revision alongside it (both in the cloud and locally) so pulls can order the
    /// writers (#766). Cheap enough to run on every defaults change: the list is short
    /// and KVS reads are in-memory.
    private func mirrorChangedToCloud() {
        for key in Self.syncedKeys {
            let local = UserDefaults.standard.object(forKey: key)
            let cloud = CloudSyncStore.shared.object(forKey: key)
            guard !Self.plistValuesEqual(local, cloud) else { continue }

            // Push only when the local side is the newest writer. A differing cloud
            // value with a newer revision is an inbound edit this device simply hasn't
            // pulled yet (this scan runs on EVERY defaults change, for every key);
            // pushing over it would stamp a fresher revision onto the stale value and
            // silently revert the other Mac's change everywhere (#1017, #1023). Adopt
            // it now instead of waiting for the external-change notification.
            let cloudRevision = CloudSyncStore.shared.object(forKey: Self.cloudRevisionKey(key)) as? Double ?? 0
            let localRevision = UserDefaults.standard.double(forKey: Self.localRevisionKey(key))
            guard cloudRevision <= localRevision else {
                pull(key: key)
                continue
            }

            let revision = Date().timeIntervalSince1970
            UserDefaults.standard.set(revision, forKey: Self.localRevisionKey(key))
            CloudSyncStore.shared.mirrorObject(local, forKey: key)
            CloudSyncStore.shared.mirrorObject(revision, forKey: Self.cloudRevisionKey(key))
        }
    }

    /// Pulls one key's cloud value into UserDefaults when it differs AND its revision
    /// stamp is at least as new as the last local write - last-writer-wins needs to
    /// know the writer order, so a newer offline local edit survives startup instead
    /// of being reverted by an older cloud copy (#766). Missing revisions count as 0,
    /// so a pre-revision cloud value still seeds a never-locally-written key (the
    /// fresh-Mac case). A missing cloud value never clears a local one (deletions
    /// don't propagate, matching the collection stores). Writing the value re-posts
    /// `didChangeNotification`, but the resulting push is a no-op because the two
    /// sides now match - this is what makes the sync converge instead of looping.
    private func pull(key: String) {
        guard let cloud = CloudSyncStore.shared.object(forKey: key) else { return }

        let local = UserDefaults.standard.object(forKey: key)
        guard !Self.plistValuesEqual(local, cloud) else { return }

        let cloudRevision = CloudSyncStore.shared.object(forKey: Self.cloudRevisionKey(key)) as? Double ?? 0
        let localRevision = UserDefaults.standard.double(forKey: Self.localRevisionKey(key))
        guard cloudRevision >= localRevision else { return }

        UserDefaults.standard.set(cloud, forKey: key)
        UserDefaults.standard.set(cloudRevision, forKey: Self.localRevisionKey(key))
        applySideEffects(forPulledKey: key)
    }

    /// Runs the side effects a locally toggled control would have run for `key`, so a
    /// pulled value behaves exactly like a local change. @AppStorage-backed UI reacts
    /// to the defaults write on its own; these are the out-of-band effects that only
    /// lived in Settings' onChange closures, which a cloud pull bypasses:
    /// the Dock activation policy for presence (#742), the badge recompute and
    /// authorization for the badge scope (#743), and the Spotlight index/clear pass
    /// for the indexing opt-in/out (#741).
    private func applySideEffects(forPulledKey key: String) {
        switch key {
        case "general.presence":
            GeneralSettings.applyDockVisibility()

        case "general.dockBadgeScope":
            applyBadgeScopeChange(key: key)

        case "general.spotlightIndexing":
            applySpotlightIndexingChange()

        case "general.notifyOnPadUpdates":
            applyNotifyOnPadUpdatesChange(key: key)

        default:
            break
        }
    }

    /// Mirrors the Settings picker (#836): a pulled non-off scope on a Mac whose badge
    /// permission is denied must revert to Off, not sit enabled-looking while nothing
    /// ever renders (#1029).
    private func applyBadgeScopeChange(key: String) {
        guard DockBadgeController.scope != .off else {
            DockBadgeController.refresh()
            return
        }

        Task { @MainActor in
            let isAvailable = await PadUpdateNotifier.shared.badgeAuthorizationIsAvailable()
            if !isAvailable, DockBadgeController.scope != .off {
                UserDefaults.standard.set(DockBadgeScope.off.rawValue, forKey: key)
            }
            DockBadgeController.refresh()
        }
    }

    /// Mirrors the Settings toggle (#836): a pulled ON on a Mac whose notification
    /// permission is denied must revert to off, or every alert is silently dropped
    /// behind an enabled-looking setting (#1027).
    private func applyNotifyOnPadUpdatesChange(key: String) {
        guard UserDefaults.standard.bool(forKey: key) else { return }

        Task { @MainActor in
            let isAvailable = await PadUpdateNotifier.shared.alertAuthorizationIsAvailable()
            if !isAvailable, UserDefaults.standard.bool(forKey: key) {
                UserDefaults.standard.set(false, forKey: key)
            }
        }
    }

    /// Mirrors the Settings toggle (#741): opting out must actually clear the index -
    /// the titles carry candidate names - and opting in seeds it from the caches.
    private func applySpotlightIndexingChange() {
        guard UserDefaults.standard.bool(forKey: "general.spotlightIndexing") else {
            SpotlightIndexer.clearAll()
            return
        }
        for account in AccountsStore.shared.accounts {
            SpotlightIndexer.updatePads(PadsCacheStore.shared.get(account.id), account: account.id)
            SpotlightIndexer.updateQuestions(QuestionsCacheStore.shared.get(account.id), account: account.id)
        }
    }

    /// The KVS key carrying `key`'s revision stamp. Internal for tests.
    static func cloudRevisionKey(_ key: String) -> String {
        "revision.\(key)"
    }

    /// The device-local UserDefaults key remembering the revision of the last write
    /// (local edit or adopted pull) for `key`. Deliberately NOT in `syncedKeys`.
    static func localRevisionKey(_ key: String) -> String {
        "cloud.revision.\(key)"
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
