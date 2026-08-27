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
              let host = url.host(), !host.isEmpty,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              // Embedded credentials can leak into browser UI, history, sync, logs, and
              // screenshots once handed to LaunchServices / UIApplication (#4663).
              components.user == nil, components.password == nil else { return false }

        return true
    }

    /// Open a link in the user's chosen browser, honoring the background preference.
    @MainActor
    static func openExternally(_ url: URL) {
        guard isOpenableWebURL(url) else {
            persistenceLogger.error("Refused to open a non-web URL externally")
            return
        }
        guard !capturedForUITesting(url) else { return }

        #if os(macOS)
            openInChosenBrowser(url)
        #else
            // iOS: no app-picking or background-open; the system routes http(s) to the
            // user's default browser. The browser-choice/background preferences are
            // macOS-only affordances and don't apply here.
            UIApplication.shared.open(url, options: [:]) { success in
                guard !success else { return }

                persistenceLogger.error("Failed to open URL in the system browser")
                Task { @MainActor in
                    reportOpenFailure(String(localized: "The browser could not open that link."))
                }
            }
        #endif
    }

    /// UI tests must prove the complete handoff URL without opening Safari (which steals
    /// focus from XCUIAutomation and makes the assertion racy). A distributed notification
    /// crosses from the tested app to the runner; this exists only under the explicit
    /// persistence-free UI-test launch argument.
    @MainActor
    private static func capturedForUITesting(_ url: URL) -> Bool {
        #if os(macOS)
            guard coderpadIsUITesting,
                  ProcessInfo.processInfo.arguments.contains("-uiTestingCaptureBrowserOpen")
            else {
                return false
            }

            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name("com.coderpad.app.uiTestingBrowserOpen"),
                object: url.absoluteString
            )
            return true
        #else
            return false
        #endif
    }

    #if os(macOS)
        /// Resolves the user's chosen browser, clearing the preference if that browser is
        /// gone (uninstalled/renamed) so Settings shows the Default choice that is actually
        /// in effect rather than an unavailable browser every link silently bypasses (#1140).
        @MainActor
        private static func resolvedBrowserURL() -> URL? {
            guard let bundleID = validatedBrowserBundleID() else { return nil }

            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                return appURL
            }

            UserDefaults.standard.removeObject(forKey: Key.defaultBrowserBundleID)
            persistenceLogger.notice(
                """
                Default browser \(bundleID, privacy: .public) is no longer installed; \
                reverting to the system default.
                """
            )
            return nil
        }

        @MainActor
        private static func openInChosenBrowser(_ url: URL) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = !openInBackground
            let chosenAppURL = resolvedBrowserURL()
            if usesUnexpectedBrowserFallback(requestedBundleID: defaultBrowserBundleID,
                                             chosenAppURL: chosenAppURL) {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = String(localized: "Your chosen browser is not available")
                alert.informativeText = String(localized: "This link will open in your system default browser instead.")
                alert.addButton(withTitle: String(localized: "Continue"))
                alert.addButton(withTitle: String(localized: "Cancel"))
                guard alert.runModal() == .alertFirstButtonReturn else { return }
            }

            guard let appURL = chosenAppURL ?? NSWorkspace.shared.urlForApplication(toOpen: probeURL) else {
                guard !NSWorkspace.shared.open(url) else { return }

                persistenceLogger.error("Failed to open URL with the system default browser")
                reportOpenFailure(String(localized: "The browser could not open that link."))
                return
            }

            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config) { _, error in
                guard let error else { return }

                persistenceLogger.error(
                    "Failed to open URL in browser: \(error.localizedDescription, privacy: .public)"
                )
                Task { @MainActor in
                    reportOpenFailure(String(localized: "The browser could not open that link."))
                }
            }
        }
    #endif

    @MainActor
    private static func reportOpenFailure(_ message: String) {
        AppNavigation.shared.browserOpenFailure = message
    }

    static func usesUnexpectedBrowserFallback(requestedBundleID: String?, chosenAppURL: URL?) -> Bool {
        requestedBundleID != nil && chosenAppURL == nil
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
            if let cachedInstalledBrowsers {
                return cachedInstalledBrowsers
            }

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
    static func systemDefaultBrowserName() -> String? {
        #if os(macOS)
            guard let appURL = NSWorkspace.shared.urlForApplication(toOpen: probeURL) else { return nil }

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
            if name.hasSuffix(".app") {
                name.removeLast(4)
            }
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

// How the app follows the system appearance, or forces light/dark regardless.
