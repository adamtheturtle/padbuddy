//
//  SettingsView+Models+Appearance.swift
//  coderpad
//
//
//  Appearance, presence and the general settings they belong to.

import os
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .system: String(localized: "System")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        }
    }

    /// The color scheme to force on the app's windows, or nil to follow the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

// AppearancePicker and AppearanceSwatch live in SettingsView+AppearancePicker.swift
// (split out for file length).

/// Where the app makes itself visible: the Dock, the menu bar, or both. Replaces the
/// older boolean "Hide Dock icon" toggle, which couldn't express "Dock only".
/// "Neither" is intentionally omitted — the app would have no visible affordance.
enum AppPresence: String, CaseIterable, Identifiable {
    case dockAndMenuBar
    case menuBarOnly
    case dockOnly

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .dockAndMenuBar: String(localized: "Dock and menu bar")
        case .menuBarOnly: String(localized: "Menu bar only")
        case .dockOnly: String(localized: "Dock only")
        }
    }

    /// Whether a Dock icon is shown — drives the activation policy and whether the
    /// Dock-badge picker is available.
    var showsDockIcon: Bool {
        switch self {
        case .dockAndMenuBar, .dockOnly: true
        case .menuBarOnly: false
        }
    }

    /// Whether the menu-bar extra is inserted.
    var showsMenuBarIcon: Bool {
        switch self {
        case .dockAndMenuBar, .menuBarOnly: true
        case .dockOnly: false
        }
    }
}

/// General app preferences stored in `UserDefaults`. Mirrors `BrowserSettings`: the
/// keys are shared by the settings UI (via `@AppStorage`) and by the app-wide static
/// getters here, so a single source of truth backs both. Launch-at-login state lives
/// with the system (`SMAppService`) rather than here — see `LoginItem`.
enum GeneralSettings {
    /// Nonisolated so off-main readers (e.g. the Spotlight operation queue, which
    /// re-checks the indexing preference at execution time, #734) can reference the
    /// key constants.
    nonisolated enum Key {
        static let appearance = "general.appearance"
        static let presence = "general.presence"
        /// Legacy boolean ("Hide Dock icon") superseded by `presence`. Read once at
        /// launch to migrate the user's choice, then removed. See `migratePresenceIfNeeded`.
        static let hideDockIcon = "general.hideDockIcon"
        static let spotlightIndexing = "general.spotlightIndexing"
        static let notifyOnPadUpdates = "general.notifyOnPadUpdates"
        static let hidePadTitlesInNotifications = "general.hidePadTitlesInNotifications"
        static let includeIdentitiesInPadExports = "general.includeIdentitiesInPadExports"
        static let showAccountEmailsInSectionHeaders = "general.showAccountEmailsInSectionHeaders"
    }

    /// Whether to post a Notification Center alert when pads gain new activity in the
    /// background. Off by default — opt-in, since it also requires the user to grant
    /// notification permission. See `PadUpdateNotifier`.
    static var notifyOnPadUpdates: Bool {
        UserDefaults.standard.bool(forKey: Key.notifyOnPadUpdates)
    }

    /// Whether to keep pad titles out of notification alerts.
    ///
    /// A pad title routinely carries a candidate's name, and an alert shows it on the
    /// lock screen and in Notification Center, where it is visible to anyone near the
    /// machine and to screen sharing (#2178). Off by default so the alert stays useful
    /// for the common case; on, alerts say only that activity happened.
    static var hidePadTitlesInNotifications: Bool {
        UserDefaults.standard.bool(forKey: Key.hidePadTitlesInNotifications)
    }

    /// Pad exports are commonly shared outside the app. Keep owner and participant
    /// identities out unless the user has deliberately opted in (#1553).
    static var includeIdentitiesInPadExports: Bool {
        UserDefaults.standard.bool(forKey: Key.includeIdentitiesInPadExports)
    }

    /// Whether pads and questions are mirrored into the on-device Spotlight index so
    /// they're findable system-wide. Off by default — pad titles can carry candidate
    /// names, so it's opt-in. See `SpotlightIndexer`.
    static var spotlightIndexing: Bool {
        UserDefaults.standard.bool(forKey: Key.spotlightIndexing)
    }

    /// Full list reads paginate through the entire organization. Ninety seconds is
    /// responsive enough for passive updates without consuming the API budget at the
    /// old four-polls-per-minute rate; manual reload remains immediate (#2886).
    static let defaultRefreshSeconds = 90

    static var appearance: AppAppearance {
        AppAppearance(rawValue: UserDefaults.standard.string(forKey: Key.appearance) ?? "") ?? .system
    }

    /// Where the app appears (Dock, menu bar, or both). Defaults to showing in both.
    static var presence: AppPresence {
        AppPresence(rawValue: UserDefaults.standard.string(forKey: Key.presence) ?? "") ?? .dockAndMenuBar
    }

    /// One-time migration of the legacy `hideDockIcon` Bool into the `presence` enum so
    /// existing users keep their choice: a hidden Dock icon maps to "Menu bar only".
    /// Runs at launch before `applyDockVisibility`; no-ops once `presence` is set.
    static func migratePresenceIfNeeded() {
        let defaults = UserDefaults.standard
        // A *present but unrecognized* presence value is not a migrated choice — it
        // reads back as the `.dockAndMenuBar` default, so skipping migration on its
        // account silently discarded a legacy "hide the Dock icon" preference (#2162).
        // Only an already-valid value means there is nothing to migrate.
        let stored = defaults.string(forKey: Key.presence)
        let alreadyMigrated = stored.flatMap(AppPresence.init(rawValue:)) != nil
        guard !alreadyMigrated, defaults.object(forKey: Key.hideDockIcon) != nil else { return }

        let presence: AppPresence = defaults.bool(forKey: Key.hideDockIcon) ? .menuBarOnly : .dockAndMenuBar
        defaults.set(presence.rawValue, forKey: Key.presence)
        defaults.removeObject(forKey: Key.hideDockIcon)
    }

    static var refreshInterval: Duration {
        .seconds(defaultRefreshSeconds)
    }

    /// Reflect the presence preference by switching the activation policy:
    /// `.regular` shows a Dock icon, `.accessory` runs menu-bar-only (no Dock icon).
    @MainActor
    static func applyDockVisibility() {
        #if os(macOS)
            NSApp.setActivationPolicy(presence.showsDockIcon ? .regular : .accessory)
        #else
            // iOS: no Dock or activation policy, so presence has no effect here.
        #endif
    }
}
