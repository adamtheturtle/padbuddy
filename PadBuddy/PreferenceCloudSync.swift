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

// swiftlint:disable file_length

import Foundation
import os

@MainActor
final class PreferenceCloudSync {
    static let shared = PreferenceCloudSync()

    var validationIssue: ValidationIssue?

    /// The UserDefaults keys that sync, gathered here so the policy is auditable in one
    /// place against the #536 inventory. Anything not listed stays device-local - most
    /// importantly credentials (handled by iCloud Keychain, not KVS) and window/UI state.
    static let syncedKeys: [String] = {
        var keys = [
            // Continuity preferences.
            "pads.sort",
            "questions.sort",
            "pads.merged.liveFilter",
            "questions.merged.liveFilter",
            // App-global settings.
            "general.appearance",
            "general.dockBadgeScope",
            "general.spotlightIndexing",
            "general.notifyOnPadUpdates",
            "general.hidePadTitlesInNotifications",
            "browser.defaultBrowserBundleID"
        ]
        #if os(macOS)
            // macOS-only behaviours stay between Macs: iOS has no menu-bar/Dock
            // presence to represent or change (#1142), and no background-open
            // affordance - syncing them wrote inert, unexplained preferences onto
            // iOS and churned KVS for nothing (#1141).
            keys += ["general.presence", "browser.openInBackground"]
        #endif
        return keys
    }()

    /// Values held back from the cloud, keyed by preference. A change the user did not
    /// deliberately make in Settings - dragging the menu-bar icon out, which the app
    /// mirrors into `presence` so the picker stays honest - should not propagate a
    /// disruptive visibility change to their other Macs (#2327). The value is recorded
    /// rather than a flag, so a later deliberate change to something else still syncs.
    private var heldLocalValues: [String: String] = [:]

    /// Records `value` as device-local for `key`: the next mirror pass skips it while
    /// the local value still matches. A deliberate change to any other value clears
    /// the hold and syncs normally.
    func holdLocal(key: String, value: String) {
        heldLocalValues[key] = value
    }

    private var defaultsObserver: (any NSObjectProtocol)?
    private var cloudObserver: (any NSObjectProtocol)?
    private var mirrorTask: Task<Void, Never>?
    private var pendingChangedKeys = Set<String>()
    private var notificationAuthorizationGeneration = 0

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

        for key in Self.syncedKeys {
            lastKnownValues[key] = UserDefaults.standard.object(forKey: key)
        }
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: UserDefaults.standard, queue: .main
        ) { _ in
            // Delivered on the posting (main) thread for the standard defaults.
            MainActor.assumeIsolated { Self.shared.scheduleMirrorIfSyncedKeyChanged() }
        }
        cloudObserver = NotificationCenter.default.addObserver(
            forName: CloudSyncStore.didChangeExternally, object: nil, queue: .main
        ) { note in
            let changedKey = note.userInfo?["key"] as? String
            MainActor.assumeIsolated {
                guard let changedKey,
                      let key = Self.preferenceKey(forCloudChangeKey: changedKey) else { return }

                Self.shared.pull(key: key)
            }
        }
    }

    /// Coalesces a burst of defaults writes into one mirror pass. Multi-step
    /// restores (e.g. applying a merged live-filter snapshot field by field) post
    /// several intermediate values; mirroring each one stamped-latest could
    /// overwrite another device's complete selection with a transient
    /// half-applied blob (#1148).
    /// The last value seen for each synced key, so an unrelated defaults write can be
    /// ruled out without a KVS round-trip.
    ///
    /// `UserDefaults.didChangeNotification` fires for *every* defaults write in the
    /// process — window frames, scene storage, the lot — and each one used to schedule
    /// a pass comparing every synced key against iCloud (#2154). Most of those passes
    /// had nothing to do. Comparing against this snapshot first is a cheap local check
    /// that skips them.
    private var lastKnownValues: [String: Any] = [:]

    /// Schedules a mirror pass only when a key we actually sync has changed.
    private func scheduleMirrorIfSyncedKeyChanged() {
        for key in Self.syncedKeys {
            let current = UserDefaults.standard.object(forKey: key)
            if !Self.plistValuesEqual(lastKnownValues[key], current) {
                lastKnownValues[key] = current
                pendingChangedKeys.insert(key)
            }
        }
        guard !pendingChangedKeys.isEmpty else { return }

        scheduleMirror()
    }

    private func scheduleMirror() {
        mirrorTask?.cancel()
        mirrorTask = Task { @MainActor in
            do {
                try await Self.waitForMirrorDebounce()
            } catch is CancellationError {
                return
            } catch {
                persistenceLogger.error("Preference cloud mirror debounce failed: \(error)")
                return
            }
            guard !Task.isCancelled else { return }

            let keys = pendingChangedKeys
            pendingChangedKeys.subtract(keys)
            mirrorChangedToCloud(keys: keys)
        }
    }

    static func waitForMirrorDebounce(using sleep: (() async throws -> Void)? = nil) async throws {
        if let sleep {
            try await sleep()
        } else {
            try await Task.sleep(for: .milliseconds(500))
        }
    }

    /// Pushes any synced key whose local value differs from the cloud copy, stamping a
    /// revision alongside it (both in the cloud and locally) so pulls can order the
    /// writers (#766). Cheap enough to run on every (debounced) defaults change: the
    /// list is short and KVS reads are in-memory.
    private func mirrorChangedToCloud(keys: Set<String>) {
        for key in keys {
            let local = UserDefaults.standard.object(forKey: key)
            guard Self.preferenceValueDisposition(local, forKey: key) != .invalid else {
                reportValidationIssue(for: key)
                persistenceLogger.error("Refused to mirror invalid local preference for \(key, privacy: .public)")
                continue
            }

            clearValidationIssue(for: key)

            let cloud = CloudSyncStore.shared.object(forKey: key)
            guard !Self.plistValuesEqual(local, cloud) else {
                heldLocalValues[key] = nil
                continue
            }

            // A value this device is deliberately keeping to itself (#2327).
            if let held = heldLocalValues[key] {
                if (local as? String) == held {
                    continue
                }

                // The user has moved on to some other value; that one is a real edit.
                heldLocalValues[key] = nil
            }

            // This key came from an observed local defaults change, so it is a genuine
            // local edit rather than an all-key scan encountering an unpulled cloud
            // value. Advance beyond both replicas; a skewed legacy timestamp can be a
            // baseline but can never permanently outrank later edits (#2791).
            let cloudRevision = Self.revision(CloudSyncStore.shared.object(forKey: Self.cloudRevisionKey(key)))
            let localRevision = UserDefaults.standard.double(forKey: Self.localRevisionKey(key))
            let revision = Self.nextRevision(local: localRevision, cloud: cloudRevision)
            UserDefaults.standard.set(revision, forKey: Self.localRevisionKey(key))
            CloudSyncStore.shared.mirrorObject(local, forKey: key)
            CloudSyncStore.shared.mirrorObject(revision, forKey: Self.cloudRevisionKey(key))
        }
    }

    /// Pulls one key's cloud value into UserDefaults when it differs AND its revision
    /// stamp orders it as the newer write - last-writer-wins needs to know the writer
    /// order, so a newer offline local edit survives startup instead of being
    /// reverted by an older cloud copy (#766). Missing revisions count as 0, so a
    /// pre-revision cloud value still seeds a never-locally-written key (the
    /// fresh-Mac case). Two devices can stamp the exact same timestamp; equal
    /// revisions with differing values break the tie deterministically by value, so
    /// every device converges on the same side instead of whichever notification
    /// arrived last winning per-device (#1147). A missing value accompanied by a
    /// positive revision is a deletion tombstone; bare absence still means never
    /// written and cannot erase a local preference (#2793).
    /// Writing the value re-posts `didChangeNotification`, but the resulting push is
    /// a no-op because the two sides now match - this is what makes the sync
    /// converge instead of looping.
    private func pull(key: String) {
        let local = UserDefaults.standard.object(forKey: key)
        let cloud = CloudSyncStore.shared.object(forKey: key)
        let cloudRevision = Self.revision(CloudSyncStore.shared.object(forKey: Self.cloudRevisionKey(key)))
        let localRevision = Self.normalizedRevision(UserDefaults.standard.double(forKey: Self.localRevisionKey(key)))

        guard let cloud else {
            guard Self.deletionWins(cloudRevision: cloudRevision,
                                    localRevision: localRevision,
                                    localExists: local != nil) else { return }

            UserDefaults.standard.removeObject(forKey: key)
            UserDefaults.standard.set(cloudRevision, forKey: Self.localRevisionKey(key))
            if local != nil {
                applySideEffects(forPulledKey: key)
            }
            return
        }
        guard Self.preferenceValueDisposition(cloud, forKey: key) == .value else {
            reportValidationIssue(for: key)
            persistenceLogger.error("Refused invalid cloud preference for \(key, privacy: .public)")
            return
        }

        clearValidationIssue(for: key)
        guard Self.shouldAdoptCloudValue(cloud, forKey: key, local: local,
                                         cloudRevision: cloudRevision,
                                         localRevision: localRevision) else { return }

        UserDefaults.standard.set(cloud, forKey: key)
        UserDefaults.standard.set(cloudRevision, forKey: Self.localRevisionKey(key))
        applySideEffects(forPulledKey: key)
    }

    /// A stored revision stamp, whatever numeric representation it came back as.
    ///
    /// `as? Double` alone failed for a value bridged as an integer-backed number,
    /// which made a valid stamp read as 0 — so a genuinely newer cloud write looked
    /// older than every local one and was never adopted (#2152). Internal for tests.
    static func revision(_ stored: Any?) -> Double {
        let value = switch stored {
        case let value as Double: value
        case let value as Int: Double(value)
        case let value as Float: Double(value)
        default: 0.0
        }
        return normalizedRevision(value)
    }

    /// The deterministic equal-revision tie-breaker (#1147): a never-written local
    /// side always adopts the cloud (the fresh-device seed), otherwise the value
    /// whose canonical description sorts higher wins - both devices compare the
    /// same two values the same way, so exactly one side adopts and they converge.
    /// Internal for tests.
    static func tieBreakFavorsCloud(local: Any?, cloud: Any) -> Bool {
        guard let local else { return true }

        let localDescription = (local as? NSObject)?.description ?? String(describing: local)
        let cloudDescription = (cloud as? NSObject)?.description ?? String(describing: cloud)
        return cloudDescription > localDescription
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
        let pulledScope = DockBadgeController.scope
        guard pulledScope != .off else {
            DockBadgeController.refresh()
            return
        }

        Task { @MainActor in
            let isAvailable = await PadUpdateNotifier.shared.badgeAuthorizationIsAvailable()
            if Self.shouldDisableBadgeScope(
                pulled: pulledScope,
                current: DockBadgeController.scope,
                authorizationIsAvailable: isAvailable
            ) {
                UserDefaults.standard.set(DockBadgeScope.off.rawValue, forKey: key)
            }
            DockBadgeController.refresh()
        }
    }

    static func shouldDisableBadgeScope(
        pulled: DockBadgeScope,
        current: DockBadgeScope,
        authorizationIsAvailable: Bool
    ) -> Bool {
        !authorizationIsAvailable && current == pulled
    }

    /// Mirrors the Settings toggle (#836): a pulled ON on a Mac whose notification
    /// permission is denied must revert to off, or every alert is silently dropped
    /// behind an enabled-looking setting (#1027).
    private func applyNotifyOnPadUpdatesChange(key: String) {
        notificationPreferenceChanged(key: key)
    }

    func notificationPreferenceChanged(key: String) {
        notificationAuthorizationGeneration &+= 1
        let generation = notificationAuthorizationGeneration
        guard UserDefaults.standard.bool(forKey: key) else {
            PadUpdateNotifier.shared.removeAllPadUpdateNotifications()
            return
        }

        Task { @MainActor in
            let isAvailable = await PadUpdateNotifier.shared.alertAuthorizationIsAvailable()
            if Self.shouldDisableNotifications(
                requestedGeneration: generation,
                currentGeneration: notificationAuthorizationGeneration,
                notificationsAreEnabled: UserDefaults.standard.bool(forKey: key),
                authorizationIsAvailable: isAvailable
            ) {
                UserDefaults.standard.set(false, forKey: key)
                PadUpdateNotifier.shared.removeAllPadUpdateNotifications()
            }
        }
    }

    static func shouldDisableNotifications(
        requestedGeneration: Int,
        currentGeneration: Int,
        notificationsAreEnabled: Bool,
        authorizationIsAvailable: Bool
    ) -> Bool {
        !authorizationIsAvailable
            && notificationsAreEnabled
            && currentGeneration == requestedGeneration
    }

    /// Mirrors the Settings toggle (#741): opting out must actually clear the index -
    /// the titles carry candidate names - and opting in seeds it from the caches.
    private func applySpotlightIndexingChange() {
        guard UserDefaults.standard.bool(forKey: "general.spotlightIndexing") else {
            SpotlightIndexer.clearAll()
            return
        }

        // A cloud opt-in commonly arrives on a fresh device before its account lists
        // have refreshed. Do not publish partial or stale disk caches as authoritative
        // search results; completed pad/question fetches already update Spotlight from
        // their persisted cache writes (#2800). Local, explicit opt-in still seeds the
        // currently visible caches immediately from Settings.
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
