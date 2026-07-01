//
//  SettingsView+Models.swift
//  coderpad
//

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif
import SwiftUI

/// Where a pad link opens when you activate it.
enum LinkDestination: String, CaseIterable, Identifiable {
    case inApp
    case external

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .inApp: String(localized: "In-app browser")
        case .external: String(localized: "Default browser")
        }
    }
}

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
        static let openLinksIn = "browser.openLinksIn"
        static let defaultBrowserBundleID = "browser.defaultBrowserBundleID"
        static let openInBackground = "browser.openInBackground"
    }

    static var openLinksIn: LinkDestination {
        LinkDestination(rawValue: UserDefaults.standard.string(forKey: Key.openLinksIn) ?? "") ?? .inApp
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
            let appURL = defaultBrowserBundleID.flatMap {
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
            } ?? NSWorkspace.shared.urlForApplication(toOpen: probeURL)
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

    /// Bundle identifier of the standalone Passwords app that ships with macOS 15+.
    private static let passwordsAppBundleID = "com.apple.Passwords"

    /// Open the macOS Passwords app so the user can look up and copy a login to paste
    /// into the in-app pad browser, where native autofill is unavailable. Falls back to
    /// the Passwords pane in System Settings on systems without the standalone app.
    @MainActor
    static func openPasswordsApp() {
        #if os(macOS)
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: passwordsAppBundleID) {
                NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
            } else if let settingsURL = URL(
                string: "x-apple.systempreferences:com.apple.Passwords-Settings.extension"
            ) {
                NSWorkspace.shared.open(settingsURL)
            }
        #else
            // iOS: there's no way to launch the Passwords app by bundle id, and the
            // in-app browser gets native AutoFill anyway, so this affordance is unneeded.
            _ = passwordsAppBundleID
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

/// General app preferences (appearance, Dock visibility, auto-refresh cadence)
/// stored in `UserDefaults`. Mirrors `BrowserSettings`: the keys are shared by the
/// settings UI (via `@AppStorage`) and by the app-wide static getters here, so a
/// single source of truth backs both. Launch-at-login state lives with the system
/// (`SMAppService`) rather than here — see `LoginItem`.
enum GeneralSettings {
    enum Key {
        static let appearance = "general.appearance"
        static let presence = "general.presence"
        /// Legacy boolean ("Hide Dock icon") superseded by `presence`. Read once at
        /// launch to migrate the user's choice, then removed. See `migratePresenceIfNeeded`.
        static let hideDockIcon = "general.hideDockIcon"
        static let refreshSeconds = "general.refreshSeconds"
        static let requireBiometricsToRevealKey = "general.requireBiometricsToRevealKey"
        static let spotlightIndexing = "general.spotlightIndexing"
        static let notifyOnPadUpdates = "general.notifyOnPadUpdates"
    }

    /// Whether to post a Notification Center alert when pads gain new activity in the
    /// background. Off by default — opt-in, since it also requires the user to grant
    /// notification permission. See `PadUpdateNotifier`.
    static var notifyOnPadUpdates: Bool {
        UserDefaults.standard.bool(forKey: Key.notifyOnPadUpdates)
    }

    // Deliberate non-SwiftUI accessor, symmetric with the other GeneralSettings flags.
    // periphery:ignore
    /// Whether revealing a saved API key in Settings must be unlocked with Touch ID
    /// (falling back to the login password). Off by default.
    static var requireBiometricsToRevealKey: Bool {
        UserDefaults.standard.bool(forKey: Key.requireBiometricsToRevealKey)
    }

    /// Whether pads and questions are mirrored into the on-device Spotlight index so
    /// they're findable system-wide. Off by default — pad titles can carry candidate
    /// names, so it's opt-in. See `SpotlightIndexer`.
    static var spotlightIndexing: Bool {
        UserDefaults.standard.bool(forKey: Key.spotlightIndexing)
    }

    /// Default auto-refresh cadence. Kept tight (15s) so pads and questions stay
    /// close to live without a manual reload (#412); users can dial it back up to
    /// 10 minutes in Settings.
    static let defaultRefreshSeconds = 15
    static let minRefreshSeconds = 15
    static let maxRefreshSeconds = 600

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

    /// Auto-refresh cadence in seconds, clamped to a sane range. A never-set value
    /// reads back as 0 from `UserDefaults`, which we treat as "use the default".
    static var refreshSeconds: Int {
        let stored = UserDefaults.standard.integer(forKey: Key.refreshSeconds)
        guard stored != 0 else { return defaultRefreshSeconds }

        return min(max(stored, minRefreshSeconds), maxRefreshSeconds)
    }

    static var refreshInterval: Duration {
        .seconds(refreshSeconds)
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
