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

    /// The stored choice, but only when it names an http(s)-capable app installed on
    /// this Mac.
    ///
    /// The raw value was handed to `NSWorkspace` as-is, so a corrupt default — or one
    /// synced from another Mac with different apps — could launch an unrelated
    /// application for every link (#2157). An identifier that doesn't correspond to a
    /// browser here falls through to the system default, which is also what the
    /// uninstalled case already did (#1140).
    @MainActor
    static func validatedBrowserBundleID() -> String? {
        #if os(macOS)
            guard let bundleID = defaultBrowserBundleID else { return nil }
            guard installedBrowsers().contains(where: { $0.bundleID == bundleID }) else {
                persistenceLogger.notice(
                    """
                    Default browser \(bundleID, privacy: .public) is not an installed web browser; \
                    reverting to the system default.
                    """
                )
                UserDefaults.standard.removeObject(forKey: Key.defaultBrowserBundleID)
                return nil
            }

            return bundleID
        #else
            return nil
        #endif
    }

    static var openInBackground: Bool {
        UserDefaults.standard.bool(forKey: Key.openInBackground)
    }

    /// A representative URL used to discover http(s)-capable apps.
    private static let probeURL = URL.staticURL("https://app.coderpad.io")

    /// Whether `url` is something this app should hand to a browser.
    ///
    /// The opener took whatever it was given, so a call site holding a `file:` or
    /// custom-scheme URL would have it opened under the browser preference (#2158).
    /// Every legitimate caller passes a web link; anything else is a bug, and refusing
    /// it here keeps that bug from becoming a launched app.
    static func isOpenableWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host(), !host.isEmpty else { return false }

        return true
    }

    /// Open a link in the user's chosen browser, honoring the background preference.
    @MainActor
    static func openExternally(_ url: URL) {
        guard isOpenableWebURL(url) else {
            persistenceLogger.error("Refused to open a non-web URL externally")
            return
        }

        #if os(macOS)
            let config = NSWorkspace.OpenConfiguration()
            config.activates = !openInBackground
            var chosenAppURL: URL?
            if let bundleID = validatedBrowserBundleID() {
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

    /// Cached result of the LaunchServices scan.
    ///
    /// The scan asks LaunchServices for every app that can open a web URL and then
    /// reads each bundle, which is slow enough to be felt — and it ran on every
    /// evaluation of the settings picker, on the main thread (#2160). The installed
    /// app set changes rarely, so the result is held until something invalidates it.
    @MainActor private static var cachedInstalledBrowsers: [InstalledBrowser]?

    /// Discards the cached scan, so a newly installed or removed browser is picked up.
    @MainActor
    static func invalidateInstalledBrowsers() {
        cachedInstalledBrowsers = nil
    }

    /// http(s)-capable apps installed on this Mac, de-duplicated and sorted by name.
    @MainActor
    static func installedBrowsers() -> [InstalledBrowser] {
        #if os(macOS)
            if let cachedInstalledBrowsers { return cachedInstalledBrowsers }

            let urls = NSWorkspace.shared.urlsForApplications(toOpen: probeURL)
            var seen = Set<String>()
            let browsers = urls.compactMap { appURL -> InstalledBrowser? in
                guard let id = Bundle(url: appURL)?.bundleIdentifier, seen.insert(id).inserted else { return nil }

                return InstalledBrowser(bundleID: id, name: displayName(for: appURL))
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            cachedInstalledBrowsers = browsers
            return browsers
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
            // Only a trailing ".app" is removed, not every occurrence: an app whose
            // name contains it (say "My.app Browser") had it cut from the middle
            // (#2161). `displayName(atPath:)` may already hide the extension, so this
            // is conditional rather than unconditional.
            var name = FileManager.default.displayName(atPath: appURL.path)
            if name.hasSuffix(".app") { name.removeLast(4) }
            let raw = name
            // Local app metadata is still input (#1618): control characters or an
            // absurdly long name must not disrupt the picker's layout or its
            // accessibility labels.
            let cleaned = String(raw.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let bounded = String(cleaned.prefix(60))
            return bounded.isEmpty ? String(localized: "Unnamed app") : bounded
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
        static let hidePadTitlesInNotifications = "general.hidePadTitlesInNotifications"
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
