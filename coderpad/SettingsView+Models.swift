//
//  SettingsView+Models.swift
//  coderpad
//

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif
import os
import SwiftUI

/// An installed app that can open http(s) links, shown in the "Default browser" picker.
struct InstalledBrowser: Identifiable, Hashable {
    let bundleID: String
    let name: String
    var id: String {
        bundleID
    }
}

/// Browser-related preferences, stored in `UserDefaults` and read both by the
/// settings UI and by the link-opening call sites across the app. Centralizing
/// these here lets a single "Open" action honor the user's choice, which is why
/// the per-location "open in default browser" buttons are no longer needed.
enum BrowserSettings {
    enum Key {
        static let defaultBrowserBundleID = "browser.defaultBrowserBundleID"
        static let openInBackground = "browser.openInBackground"
    }

    static var defaultBrowserBundleID: String? {
        UserDefaults.standard.string(forKey: Key.defaultBrowserBundleID)
    }

    static var openInBackground: Bool {
        UserDefaults.standard.bool(forKey: Key.openInBackground)
    }

    /// A representative URL used to discover http(s)-capable apps.
    private static let probeURL = URL.staticURL("https://app.coderpad.io")

    /// Open a link in the user's chosen browser, honoring the background preference.
    @MainActor
    static func openExternally(_ url: URL) {
        #if os(macOS)
            let config = NSWorkspace.OpenConfiguration()
            config.activates = !openInBackground
            var chosenAppURL: URL?
            if let bundleID = defaultBrowserBundleID {
                chosenAppURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
                if chosenAppURL == nil {
                    // The chosen browser is gone (uninstalled/renamed): clear the
                    // stale preference so Settings shows the Default choice that's
                    // actually in effect, instead of displaying an unavailable
                    // browser while every link silently opens elsewhere (#1140).
                    UserDefaults.standard.removeObject(forKey: Key.defaultBrowserBundleID)
                    persistenceLogger.notice(
                        """
                        Default browser \(bundleID, privacy: .public) is no longer installed; \
                        reverting to the system default.
                        """
                    )
                }
            }
            let appURL = chosenAppURL ?? NSWorkspace.shared.urlForApplication(toOpen: probeURL)
            if let appURL {
                NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config)
            } else {
                NSWorkspace.shared.open(url)
            }
        #else
            // iOS: no app-picking or background-open; the system routes http(s) to the
            // user's default browser. The browser-choice/background preferences are
            // macOS-only affordances and don't apply here.
            UIApplication.shared.open(url)
        #endif
    }

    /// http(s)-capable apps installed on this Mac, de-duplicated and sorted by name.
    static func installedBrowsers() -> [InstalledBrowser] {
        #if os(macOS)
            let urls = NSWorkspace.shared.urlsForApplications(toOpen: probeURL)
            var seen = Set<String>()
            return urls.compactMap { appURL -> InstalledBrowser? in
                guard let id = Bundle(url: appURL)?.bundleIdentifier, seen.insert(id).inserted else { return nil }

                return InstalledBrowser(bundleID: id, name: displayName(for: appURL))
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        #else
            // iOS: apps can't enumerate other installed apps, and the system owns the
            // default-browser choice, so there's nothing to pick from here.
            return []
        #endif
    }

    /// The name of the system's current default browser, e.g. "Safari".
    static func systemDefaultBrowserName() -> String {
        #if os(macOS)
            guard let appURL = NSWorkspace.shared.urlForApplication(toOpen: probeURL) else { return "Safari" }

            return displayName(for: appURL)
        #else
            // iOS: the default browser isn't queryable; Safari is the safe label.
            return "Safari"
        #endif
    }

    #if os(macOS)
        private static func displayName(for appURL: URL) -> String {
            FileManager.default.displayName(atPath: appURL.path)
                .replacingOccurrences(of: ".app", with: "")
        }
    #endif
}

/// How the app follows the system appearance, or forces light/dark regardless.
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
    }

    /// Whether to post a Notification Center alert when pads gain new activity in the
    /// background. Off by default — opt-in, since it also requires the user to grant
    /// notification permission. See `PadUpdateNotifier`.
    static var notifyOnPadUpdates: Bool {
        UserDefaults.standard.bool(forKey: Key.notifyOnPadUpdates)
    }

    /// Whether pads and questions are mirrored into the on-device Spotlight index so
    /// they're findable system-wide. Off by default — pad titles can carry candidate
    /// names, so it's opt-in. See `SpotlightIndexer`.
    static var spotlightIndexing: Bool {
        UserDefaults.standard.bool(forKey: Key.spotlightIndexing)
    }

    /// Fixed auto-refresh cadence. Kept tight (15s) so pads and questions stay
    /// close to live without a manual reload (#412).
    static let defaultRefreshSeconds = 15

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
        guard defaults.string(forKey: Key.presence) == nil,
              defaults.object(forKey: Key.hideDockIcon) != nil else { return }

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
