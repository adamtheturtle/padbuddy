//
//  AppLaunch.swift
//  coderpad
//

import Foundation

/// One-time, app-global launch seeding that has no dependency on `NSApp` having
/// finished launching. Called once from `CoderpadApp.init()` so it runs at process
/// launch regardless of which scene (if any) opens — unlike a scene `.task`, which
/// never fires in Dock-only / menu-bar-only presence modes where no window appears.
///
/// The genuinely AppKit-coupled, timing-sensitive launch work stays in
/// ``AppDelegate/applicationDidFinishLaunching(_:)`` (Dock activation policy and the
/// macOS Services provider), as does the Dock menu and the windowless keep-alive —
/// none of which have a SwiftUI scene equivalent (#286).
enum AppLaunch {
    /// Held for the app's lifetime: the sync bootstrap re-runs on every iCloud
    /// identity change until quit (#765).
    private static var identityObserver: (any NSObjectProtocol)?

    /// Runs the launch seeding exactly once. `CoderpadApp.init()` runs before the
    /// delegate's `applicationDidFinishLaunching(_:)`, so any preference migrations
    /// here are in place before the delegate reads them (e.g. `applyDockVisibility`).
    static func run() {
        // Carry an existing "Hide Dock icon" choice into the new presence preference.
        // The delegate applies the resulting visibility once the app has launched.
        GeneralSettings.migratePresenceIfNeeded()
        // Carry an old on/off Dock-badge choice into the new scope preference (#399),
        // then seed the badge from whatever pads are already cached; it refreshes again
        // as each account's list loads.
        DockBadgeController.migrateScopeIfNeeded()
        // The Dock badge only renders for an app granted the `.badge` capability
        // (macOS Monterey+, #317), so ask for it when the badge is in use. Idempotent,
        // so re-requesting every launch is harmless.
        if DockBadgeController.scope != .off { PadUpdateNotifier.shared.requestBadgeAuthorization() }
        DockBadgeController.refresh()
        // Mirror every account's favourite questions into the App Group up front so the
        // Recent Pads widget's "New Pad question" picker is populated even before any
        // Questions section has been opened this session (#411). The per-account sync
        // otherwise only fires when an account's questions load or a favourite toggles.
        WidgetSync.syncAllFavorites(AccountsStore.shared.accounts)
        startCloudSync()
        // Signing into iCloud while the app is running must start sync too: the
        // bootstrap above returns immediately without an identity token and was
        // never retried, so favorites/preferences silently didn't sync until a
        // relaunch (#765). Everything startCloudSync() runs is idempotent, so
        // re-running it on an identity change is safe.
        identityObserver = NotificationCenter.default.addObserver(
            forName: .NSUbiquityIdentityDidChange, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in startCloudSync() }
        }
        // Keep the current account's pads fresh on a timer even when no window is open
        // and the menu is never clicked — the one state where nothing else fetches.
        // Writing to PadsCacheStore cascades to the widget snapshot and Dock badge.
        PadsBackgroundRefresher.shared.start()
        // Clean up caches, Spotlight, favorites, and open-history when a pad or
        // question deletion is broadcast — process-wide, so a delete from a
        // standalone detail window works even when no list view is mounted (#721).
        DeletionCleanup.start()
        // Watch network reachability so the app can drop into a read-only mode while
        // CoderPad is unreachable, surfacing an offline banner and disabling edits (#321).
        NetworkMonitor.shared.start()
        // Sweep Screen report PDFs a previous run staged for viewing but didn't get to
        // delete (quit before the scheduled removal fired) - they hold candidate data
        // and must not linger in temporary storage (#807).
        ScreenReportFiles.cleanUpLeftovers()
        // Become the notification-center delegate so taps on pad-update alerts route
        // back into the app. Posting itself is opt-in (see `PadUpdateNotifier`).
        PadUpdateNotifier.shared.register()
        // Start Sparkle's updater so scheduled background update checks run from
        // launch (#28). App Store builds must not link or embed Sparkle.
        #if !APP_STORE && canImport(BuddySparkleUpdater)
            SoftwareUpdater.shared.start()
        #endif
    }

    /// Start mirroring favourites through iCloud's key-value store and pull any
    /// cloud state now that accounts are loaded (the sync id maps cloud entries
    /// back to local accounts). A no-op on the Developer ID build, which can't
    /// carry the profile-gated iCloud entitlement (#536), and whenever no iCloud
    /// identity is present - which is why the identity-change observer re-runs
    /// it (#765).
    private static func startCloudSync() {
        CloudSyncStore.shared.start()
        FavoritePadsStore.shared.syncFromCloud()
        FavoriteQuestionsStore.shared.syncFromCloud()
        FavoritesOrderStore.shared.syncFromCloud()
        PadOpenedStore.shared.syncFromCloud()
        PreferenceCloudSync.shared.start()
    }
}
