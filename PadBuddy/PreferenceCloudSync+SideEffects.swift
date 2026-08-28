//
//  PreferenceCloudSync+SideEffects.swift
//  coderpad
//
//  What a pulled preference has to do beyond landing in UserDefaults: badge and
//  notification permission, and the Spotlight index.
//

import Foundation
import os

@MainActor
extension PreferenceCloudSync {
    /// Runs the side effects a locally toggled control would have run for `key`, so a
    /// pulled value behaves exactly like a local change. @AppStorage-backed UI reacts
    /// to the defaults write on its own; these are the out-of-band effects that only
    /// lived in Settings' onChange closures, which a cloud pull bypasses:
    /// the Dock activation policy for presence (#742), the badge recompute and
    /// authorization for the badge scope (#743), and the Spotlight index/clear pass
    /// for the indexing opt-in/out (#741).
    func applySideEffects(forPulledKey key: String) {
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
                // Device-local. Badge permission is per-device, so mirroring this revert
                // turned badges off on every other Mac the user owns — the opposite of
                // the "revert locally" this is for (#4722).
                holdLocal(key: key, value: DockBadgeScope.off.rawValue)
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
                // Device-local, as for the badge scope: notification permission is
                // per-device, and one denied Mac must not turn pad-update alerts off
                // everywhere else (#4722).
                holdLocal(key: key, value: false)
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
}
