//
//  SettingsView.swift
//  coderpad
//

import AppKit
import LocalAuthentication
import ServiceManagement
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
        case .inApp: "In-app browser"
        case .external: "Default browser"
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
    private static let probeURL = URL(string: "https://app.coderpad.io")!

    /// Open a link in the user's chosen browser, honoring the background preference.
    @MainActor
    static func openExternally(_ url: URL) {
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
    }

    /// Bundle identifier of the standalone Passwords app that ships with macOS 15+.
    private static let passwordsAppBundleID = "com.apple.Passwords"

    /// Open the macOS Passwords app so the user can look up and copy a login to paste
    /// into the in-app pad browser, where native autofill is unavailable. Falls back to
    /// the Passwords pane in System Settings on systems without the standalone app.
    @MainActor
    static func openPasswordsApp() {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: passwordsAppBundleID) {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
        } else if let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Passwords-Settings.extension") {
            NSWorkspace.shared.open(settingsURL)
        }
    }

    /// http(s)-capable apps installed on this Mac, de-duplicated and sorted by name.
    static func installedBrowsers() -> [InstalledBrowser] {
        let urls = NSWorkspace.shared.urlsForApplications(toOpen: probeURL)
        var seen = Set<String>()
        return urls.compactMap { appURL -> InstalledBrowser? in
            guard let id = Bundle(url: appURL)?.bundleIdentifier, seen.insert(id).inserted else { return nil }
            return InstalledBrowser(bundleID: id, name: displayName(for: appURL))
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The name of the system's current default browser, e.g. "Safari".
    static func systemDefaultBrowserName() -> String {
        guard let appURL = NSWorkspace.shared.urlForApplication(toOpen: probeURL) else { return "Safari" }
        return displayName(for: appURL)
    }

    private static func displayName(for appURL: URL) -> String {
        FileManager.default.displayName(atPath: appURL.path)
            .replacingOccurrences(of: ".app", with: "")
    }
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
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
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

/// General app preferences (appearance, Dock visibility, auto-refresh cadence)
/// stored in `UserDefaults`. Mirrors `BrowserSettings`: the keys are shared by the
/// settings UI (via `@AppStorage`) and by the app-wide static getters here, so a
/// single source of truth backs both. Launch-at-login state lives with the system
/// (`SMAppService`) rather than here — see `LoginItem`.
enum GeneralSettings {
    enum Key {
        static let appearance = "general.appearance"
        static let hideDockIcon = "general.hideDockIcon"
        static let refreshSeconds = "general.refreshSeconds"
        static let requireBiometricsToRevealKey = "general.requireBiometricsToRevealKey"
        static let spotlightIndexing = "general.spotlightIndexing"
    }

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

    /// Default auto-refresh cadence, matching the value the panes used before this
    /// became configurable.
    static let defaultRefreshSeconds = 90
    static let minRefreshSeconds = 15
    static let maxRefreshSeconds = 600

    static var appearance: AppAppearance {
        AppAppearance(rawValue: UserDefaults.standard.string(forKey: Key.appearance) ?? "") ?? .system
    }

    static var hideDockIcon: Bool {
        UserDefaults.standard.bool(forKey: Key.hideDockIcon)
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

    /// Reflect the Dock-visibility preference by switching the activation policy:
    /// `.accessory` runs menu-bar-only (no Dock icon), `.regular` shows in the Dock.
    @MainActor
    static func applyDockVisibility() {
        NSApp.setActivationPolicy(hideDockIcon ? .accessory : .regular)
    }
}

/// Thin wrapper over `SMAppService.mainApp` for the "Launch at login" toggle. The
/// enabled state is owned by the system, so reads go straight to the service rather
/// than to `UserDefaults`.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

/// The tabs in the Settings window, used to drive `SettingsView`'s selection so
/// callers can open Settings on a specific tab (e.g. the unauthorized banner jumps
/// straight to Accounts).
enum SettingsTab: Hashable {
    case general
    case accounts
    case browser
    case menuBar
}

/// Shared target tab for the Settings window. Set this before calling `openSettings()`
/// to control which tab appears. Lives outside the view because the banner that opens
/// Settings and the `SettingsView` itself are in separate scenes.
@MainActor
@Observable
final class SettingsNavigation {
    static let shared = SettingsNavigation()
    var selectedTab: SettingsTab = .general
    /// When set, Settings opens the editor for this account as it appears, then
    /// clears it. Lets the unauthorized banner jump straight to the account's settings.
    var accountToEdit: UUID?
    private init() {}
}

struct SettingsView: View {
    @State var store = AccountsStore.shared
    @State var navigation = SettingsNavigation.shared
    @State var selectedAccountID: UUID?
    /// A not-yet-saved account being added. While non-nil, the detail pane shows the
    /// editor for it and the sidebar selection is cleared — mirroring Mail, where the
    /// `+` button reveals an inline setup pane rather than a modal sheet.
    @State var addingAccount: Account?

    // Browser and menu-bar preferences live in UserDefaults under the keys defined
    // in `BrowserSettings.Key`; `@AppStorage` reads/writes those same keys so the
    // app-wide static getters on `BrowserSettings` stay in sync.
    @AppStorage(BrowserSettings.Key.openLinksIn) var openLinksIn: LinkDestination = .inApp
    @AppStorage(BrowserSettings.Key.defaultBrowserBundleID) var defaultBrowserBundleID: String?
    @AppStorage(BrowserSettings.Key.openInBackground) var openInBackground = false
    @AppStorage("menuBarTopN") var menuBarTopN = 3
    @AppStorage("menuBarStartedOnly") var menuBarStartedOnly = false

    // General preferences, backed by the keys in `GeneralSettings.Key`.
    @AppStorage(GeneralSettings.Key.appearance) var appearance: AppAppearance = .system
    @AppStorage(GeneralSettings.Key.hideDockIcon) var hideDockIcon = false
    @AppStorage(GeneralSettings.Key.refreshSeconds) var refreshSeconds = GeneralSettings.defaultRefreshSeconds
    @AppStorage(GeneralSettings.Key.requireBiometricsToRevealKey) var requireBiometricsToRevealKey = false
    @AppStorage(GeneralSettings.Key.spotlightIndexing) var spotlightIndexing = false
    @State var accountsStore = AccountsStore.shared

    // Launch-at-login mirrors the live `SMAppService` state rather than UserDefaults,
    // so it's plain view state kept in sync on appear and after each toggle.
    @State var launchAtLogin = LoginItem.isEnabled
    @State var loginItemError: String?

    var body: some View {
        TabView(selection: $navigation.selectedTab) {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            accountsTab
                .tabItem { Label("Accounts", systemImage: "person.crop.circle") }
                .tag(SettingsTab.accounts)
            browserTab
                .tabItem { Label("Browser", systemImage: "safari") }
                .tag(SettingsTab.browser)
            menuBarTab
                .tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }
                .tag(SettingsTab.menuBar)
        }
        .frame(minWidth: 620, minHeight: 440)
        // A caller (e.g. the unauthorized banner) can request the editor for a
        // specific account; honor it both when Settings first appears and while it's
        // already open.
        .onAppear { openPendingEdit(navigation.accountToEdit) }
        .onChange(of: navigation.accountToEdit) { _, id in openPendingEdit(id) }
    }

    /// Binding for the "Require Touch ID to reveal API keys" toggle. Turning the gate
    /// *on* is free, but turning it *off* removes the protection, so the disable path is
    /// itself gated behind a Touch ID (or password) check — otherwise anyone at an
    /// unlocked Mac could simply switch it off and then reveal the key, defeating the
    /// point. The value flips to off only once authentication succeeds; a failed or
    /// cancelled prompt leaves it on. If the device can't evaluate the policy (no
    /// biometrics and no passcode), allow the change rather than trap the user.
    var biometricGateBinding: Binding<Bool> {
        Binding(
            get: { requireBiometricsToRevealKey },
            set: { newValue in
                guard !newValue else {
                    requireBiometricsToRevealKey = true
                    return
                }
                let context = LAContext()
                var policyError: NSError?
                guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
                    requireBiometricsToRevealKey = false
                    return
                }
                Task {
                    let success = await (try? context.evaluatePolicy(
                        .deviceOwnerAuthentication,
                        localizedReason: "Turn off Touch ID protection for your saved API key"
                    )) ?? false
                    if success { requireBiometricsToRevealKey = false }
                }
            }
        )
    }

    /// Reveal a requested account in the Accounts tab, switching tabs and selecting
    /// the row so its inline editor appears, then clearing the request so it fires
    /// only once.
    private func openPendingEdit(_ id: UUID?) {
        guard let id, store.accounts.contains(where: { $0.id == id }) else { return }
        navigation.selectedTab = .accounts
        addingAccount = nil
        selectedAccountID = id
        navigation.accountToEdit = nil
    }
}

#Preview { SettingsView() }
