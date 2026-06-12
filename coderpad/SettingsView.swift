//
//  SettingsView.swift
//  coderpad
//

import SwiftUI
import AppKit
import ServiceManagement
import LocalAuthentication

/// Where a pad link opens when you activate it.
enum LinkDestination: String, CaseIterable, Identifiable {
    case inApp
    case external

    var id: String { rawValue }

    var label: String {
        switch self {
        case .inApp: return "In-app browser"
        case .external: return "Default browser"
        }
    }
}

/// An installed app that can open http(s) links, shown in the "Default browser" picker.
struct InstalledBrowser: Identifiable, Hashable {
    let bundleID: String
    let name: String
    var id: String { bundleID }
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

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// The color scheme to force on the app's windows, or nil to follow the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
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
    }

    /// Whether revealing a saved API key in Settings must be unlocked with Touch ID
    /// (falling back to the login password). Off by default.
    static var requireBiometricsToRevealKey: Bool {
        UserDefaults.standard.bool(forKey: Key.requireBiometricsToRevealKey)
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

    static var refreshInterval: Duration { .seconds(refreshSeconds) }

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
    @State private var store = AccountsStore.shared
    @State private var navigation = SettingsNavigation.shared
    @State private var selectedAccountID: UUID?
    /// A not-yet-saved account being added. While non-nil, the detail pane shows the
    /// editor for it and the sidebar selection is cleared — mirroring Mail, where the
    /// `+` button reveals an inline setup pane rather than a modal sheet.
    @State private var addingAccount: Account?

    // Browser and menu-bar preferences live in UserDefaults under the keys defined
    // in `BrowserSettings.Key`; `@AppStorage` reads/writes those same keys so the
    // app-wide static getters on `BrowserSettings` stay in sync.
    @AppStorage(BrowserSettings.Key.openLinksIn) private var openLinksIn: LinkDestination = .inApp
    @AppStorage(BrowserSettings.Key.defaultBrowserBundleID) private var defaultBrowserBundleID: String?
    @AppStorage(BrowserSettings.Key.openInBackground) private var openInBackground = false
    @AppStorage("menuBarTopN") private var menuBarTopN = 3
    @AppStorage("menuBarStartedOnly") private var menuBarStartedOnly = false

    // General preferences, backed by the keys in `GeneralSettings.Key`.
    @AppStorage(GeneralSettings.Key.appearance) private var appearance: AppAppearance = .system
    @AppStorage(GeneralSettings.Key.hideDockIcon) private var hideDockIcon = false
    @AppStorage(GeneralSettings.Key.refreshSeconds) private var refreshSeconds = GeneralSettings.defaultRefreshSeconds
    @AppStorage(GeneralSettings.Key.requireBiometricsToRevealKey) private var requireBiometricsToRevealKey = false

    // Launch-at-login mirrors the live `SMAppService` state rather than UserDefaults,
    // so it's plain view state kept in sync on appear and after each toggle.
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginItemError: String?

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

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            try LoginItem.setEnabled(enabled)
                            loginItemError = nil
                        } catch {
                            // Registration failed: snap the toggle back to the real
                            // state and surface why.
                            launchAtLogin = LoginItem.isEnabled
                            loginItemError = error.localizedDescription
                        }
                    }
            } footer: {
                if let loginItemError {
                    Text(loginItemError).foregroundStyle(.red)
                } else {
                    Text("Open CoderPad automatically when you log in to your Mac.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            }

            Section {
                Toggle("Hide Dock icon", isOn: $hideDockIcon)
                    .onChange(of: hideDockIcon) { _, _ in
                        GeneralSettings.applyDockVisibility()
                    }
            } footer: {
                Text("Run CoderPad from the menu bar only. The app stays available from its menu-bar icon.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Require Touch ID to reveal API keys", isOn: $requireBiometricsToRevealKey)
            } footer: {
                Text("When on, showing a saved API key in Settings must be unlocked with Touch ID (or your login password on Macs without it).")
                    .foregroundStyle(.secondary)
            }

            Section {
                Stepper(value: $refreshSeconds,
                        in: GeneralSettings.minRefreshSeconds...GeneralSettings.maxRefreshSeconds,
                        step: 15) {
                    HStack {
                        Text("Auto-refresh interval")
                        Spacer()
                        Text(refreshIntervalLabel)
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("How often pads and questions reload in the background. Large organizations refresh less often automatically.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        // Re-sync with the system in case the login item changed outside the app.
        .onAppear { launchAtLogin = LoginItem.isEnabled }
    }

    /// Human-readable form of the auto-refresh interval, e.g. "90s" or "2m 30s".
    private var refreshIntervalLabel: String {
        let seconds = refreshSeconds
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        let remainder = seconds % 60
        return remainder == 0 ? "\(minutes)m" : "\(minutes)m \(remainder)s"
    }

    /// Mail-style master-detail layout: a sidebar listing the accounts with `+`/`−`
    /// controls at its foot, and a detail pane showing the selected account's settings
    /// inline rather than in a modal sheet.
    private var accountsTab: some View {
        HSplitView {
            accountsSidebar
                .frame(minWidth: 200, idealWidth: 220, maxWidth: 320)
            accountDetail
                .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
        }
        // Land on the active account so its settings are visible on open.
        .onAppear {
            if selectedAccountID == nil {
                selectedAccountID = store.currentAccountID
            }
        }
        // Adding a new account happens in a modal sheet; on Save it's committed to the
        // store and selected so it lands on its own row.
        .sheet(item: $addingAccount) { account in
            AccountEditor(
                initial: account,
                onSave: { updated in
                    store.add(updated)
                    addingAccount = nil
                    selectedAccountID = updated.id
                },
                onCancel: { addingAccount = nil }
            )
        }
    }

    private var accountsSidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selectedAccountID) {
                ForEach(store.accounts) { account in
                    AccountRow(
                        account: account,
                        isCurrent: account.id == store.currentAccountID
                    )
                    .tag(account.id)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            Divider()

            sidebarToolbar
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
        }
    }

    private var sidebarToolbar: some View {
        HStack(spacing: 2) {
            Button {
                addingAccount = Account(name: "", apiKey: "")
            } label: {
                Image(systemName: "plus")
            }
            .help("Add account")
            .accessibilityLabel("Add account")

            Button {
                if let id = selectedAccountID {
                    store.remove(id: id)
                    selectedAccountID = nil
                }
            } label: {
                Image(systemName: "minus")
            }
            .help("Remove selected account")
            .disabled(selectedAccountID == nil)
            .accessibilityLabel("Remove selected account")

            Spacer()

            #if DEBUG
            Menu {
                Button("Mock data") { store.addDemoIfMissing() }
                    .disabled(store.accounts.contains(where: { $0.isMock && !$0.isBadKeyDemo }))
                Button("Bad API key") { store.addDemoBadKeyIfMissing() }
                    .disabled(store.accounts.contains(where: { $0.isBadKeyDemo }))
            } label: {
                Image(systemName: "wand.and.stars")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Add a sandbox account backed by mock data, or one that simulates a revoked key (DEBUG builds only).")
            #endif
        }
        .buttonStyle(.borderless)
    }

    @ViewBuilder
    private var accountDetail: some View {
        if let id = selectedAccountID,
                  let account = store.accounts.first(where: { $0.id == id }) {
            // Editing a saved account. `onUse` makes it the active account (Mail's
            // "Enable this account"); `.id(id)` reloads the draft when the selection
            // changes so edits don't bleed between accounts.
            AccountEditor(
                initial: account,
                embedded: true,
                isCurrent: id == store.currentAccountID,
                onUse: { store.currentAccountID = id },
                onSave: { updated in store.update(updated) },
                onCancel: {},
                onDelete: {
                    store.remove(id: id)
                    selectedAccountID = nil
                }
            )
            .id(id)
        } else {
            accountDetailPlaceholder
        }
    }

    @ViewBuilder
    private var accountDetailPlaceholder: some View {
        if store.accounts.isEmpty {
            ContentUnavailableView {
                Label("No accounts", systemImage: "person.crop.circle.badge.questionmark")
            } description: {
                Text("Add an account with a CoderPad API key.")
            } actions: {
                Button("Add Account") {
                    addingAccount = Account(name: "", apiKey: "")
                }
                .buttonStyle(.borderedProminent)
                // Surface where to obtain a key for someone who doesn't have one yet.
                GetAPIKeyLink()
                    .font(.callout)
            }
        } else {
            ContentUnavailableView {
                Label("No Account Selected", systemImage: "person.crop.circle")
            }
        }
    }

    private var browserTab: some View {
        Form {
            Section {
                Picker("Open links", selection: $openLinksIn) {
                    ForEach(LinkDestination.allCases) { destination in
                        Text(destination.label).tag(destination)
                    }
                }
            }
            Section {
                Picker("Default browser", selection: $defaultBrowserBundleID) {
                    Text("Use system default (\(BrowserSettings.systemDefaultBrowserName()))")
                        .tag(String?.none)
                    ForEach(BrowserSettings.installedBrowsers()) { browser in
                        Text(browser.name).tag(Optional(browser.bundleID))
                    }
                }
            }
            Section {
                Toggle("Open links in background", isOn: $openInBackground)
            } footer: {
                Text("Please note that some third-party browsers do not support opening links in the background.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var menuBarTab: some View {
        Form {
            Section {
                Stepper(value: $menuBarTopN, in: 0...30, step: 1) {
                    HStack {
                        Text("Recent pads in menu bar")
                        Spacer()
                        Text("\(menuBarTopN)")
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Controls how many recent pads and questions appear in the menu bar item.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show only started pads", isOn: $menuBarStartedOnly)
            } footer: {
                Text("When on, the menu bar lists only your active (started) pads, hiding ended and pending ones.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AccountRow: View {
    let account: Account
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 10) {
            AvatarCircle(label: account.name, diameter: 30,
                         tint: account.isMock ? .purple : .accentColor)

            HStack(spacing: 6) {
                Text(account.name.isEmpty ? "Untitled account" : account.name)
                    .font(.callout.weight(.medium))
                if account.isMock {
                    Text("Demo")
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.purple.opacity(0.18), in: Capsule())
                        .foregroundStyle(.purple)
                }
                if account.isBadKeyDemo {
                    Text("Bad key")
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.red.opacity(0.18), in: Capsule())
                        .foregroundStyle(.red)
                }
                if isCurrent {
                    Text("Current")
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.green.opacity(0.18), in: Capsule())
                        .foregroundStyle(.green)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

enum ValidationState: Equatable {
    case idle
    case validating
    case valid(String)
    case invalid(String)
}

struct AccountEditor: View {
    @State var draft: Account
    let initialName: String
    /// When true, the editor is embedded inline in the Accounts pane (Mail-style)
    /// rather than presented as a modal sheet: it drops the fixed sheet frame, hides
    /// Cancel for saved accounts, and shows the "Use This Account" header control.
    let embedded: Bool
    /// Whether this account is the app's active one, shown as a badge in the header.
    let isCurrent: Bool
    /// Supplied only for a saved account in embedded mode; makes it the active account.
    let onUse: (() -> Void)?
    let onSave: (Account) -> Void
    let onCancel: () -> Void
    /// Supplied only when editing a saved account; `nil` hides the Delete button (Add mode).
    let onDelete: (() -> Void)?
    /// The credentials the editor opened with. A saved account can be re-saved without
    /// re-validating as long as these are untouched (e.g. a Description-only change);
    /// changing either forces a fresh validation before Save re-enables.
    private let initialAPIKey: String
    private let initialBaseURL: String?
    @State private var validation: ValidationState = .idle
    @State private var orgUsers: [OrganizationUser] = []
    @State private var showDeleteConfirmation = false
    /// Reveals the API key as plain text on explicit request. The field is a
    /// `SecureField` by default so macOS offers password AutoFill suggestions;
    /// revealing it via a toggle (rather than on focus) keeps that intact.
    @State private var revealKey = false
    /// When set in General settings, revealing a saved key first requires a
    /// successful Touch ID (or password) check — see `toggleReveal`.
    @AppStorage(GeneralSettings.Key.requireBiometricsToRevealKey) private var requireBiometricsToRevealKey = false

    init(initial: Account,
         embedded: Bool = false,
         isCurrent: Bool = false,
         onUse: (() -> Void)? = nil,
         onSave: @escaping (Account) -> Void,
         onCancel: @escaping () -> Void,
         onDelete: (() -> Void)? = nil) {
        _draft = State(initialValue: initial)
        self.initialName = initial.name
        self.initialAPIKey = initial.apiKey
        self.initialBaseURL = initial.baseURL
        self.embedded = embedded
        self.isCurrent = isCurrent
        self.onUse = onUse
        self.onSave = onSave
        self.onCancel = onCancel
        self.onDelete = onDelete
    }

    /// Reveals or hides the key. Hiding is immediate; revealing is gated behind a
    /// Touch ID / password check when the user enabled that in General settings.
    /// If the device can't evaluate the policy (no biometrics and no passcode set),
    /// reveal anyway rather than lock the user out of their own key.
    private func toggleReveal() {
        if revealKey { revealKey = false; return }
        guard requireBiometricsToRevealKey else { revealKey = true; return }
        let context = LAContext()
        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            revealKey = true
            return
        }
        Task {
            let success = (try? await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Reveal your saved CoderPad API key")) ?? false
            if success { revealKey = true }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                // Only the modal Add sheet carries a title; the embedded editor shows
                // the account's identity in the sidebar already, so it omits one and
                // leads with the Use/Current control instead.
                if !embedded {
                    Text("Add account").font(.title3.bold())
                }
                Spacer()
                if let onUse {
                    if isCurrent {
                        Label("Current", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.callout)
                    } else {
                        Button("Use This Account", action: onUse)
                            .help("Switch the app to this account.")
                    }
                }
            }
            // Reserve the button's height so swapping it for the shorter "Current"
            // label between accounts doesn't shift the rest of the form.
            .frame(minHeight: 24)
            // A flat, Mail-style pane: a right-aligned label column with left-aligned,
            // bordered fields beside it — rather than a grouped form that pushes values
            // to the trailing edge.
            VStack(alignment: .leading, spacing: 10) {
                fieldRow("API Key") {
                    HStack(spacing: 6) {
                        Group {
                            if revealKey {
                                TextField("", text: $draft.apiKey, prompt: Text("Paste your API key"))
                            } else {
                                SecureField("", text: $draft.apiKey, prompt: Text("Paste your API key"))
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.password)
                        Button {
                            toggleReveal()
                        } label: {
                            Image(systemName: revealKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                        .help(revealKey ? "Hide the API key." : "Show the API key.")
                        .accessibilityLabel(revealKey ? "Hide API key" : "Show API key")
                    }
                }
                fieldRow("Server URL") {
                    TextField("", text: baseURLBinding,
                              prompt: Text(CoderPadClient.defaultBaseURL.absoluteString))
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .help("Override only for self-hosted or regional CoderPad deployments. Leave blank to use the default.")
                }
                // A saved account always offers its Description so it can be renamed
                // without re-validating the key; a new account auto-fills it from the
                // organization once the key validates.
                if isEditing || isValidated {
                    fieldRow("Description") {
                        TextField("", text: $draft.name,
                                  prompt: Text("Auto-filled from your organization"))
                            .textFieldStyle(.roundedBorder)
                    }
                }
                // The email picker needs the validated org's member list, so it stays
                // gated behind a successful validation.
                if isValidated {
                    fieldRow("Your Email") {
                        VStack(alignment: .leading, spacing: 4) {
                            OrgMemberPicker(
                                selection: $draft.userEmail,
                                options: emailOptions,
                                label: emailLabel
                            )
                            .help("Identifies you for the My Pads and My Questions filters and the menu bar. Required to save.")
                            if !hasEmail {
                                Text("Required — pick which member you are to finish.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                fieldRow("") {
                    GetAPIKeyLink()
                        .font(.callout)
                }
            }

            validationBanner

            HStack {
                if onDelete != nil {
                    Button("Delete", role: .destructive) { showDeleteConfirmation = true }
                        .help("Remove this account and its stored API key from this Mac.")
                }
                Spacer()
                // A saved account embedded inline has no Cancel: selecting away simply
                // discards unsaved edits, the way Mail's account pane works.
                if !(embedded && onDelete != nil) {
                    Button("Cancel", role: .cancel, action: onCancel)
                }
                validateButton
                saveButton
            }
        }
        .padding()
        .frame(minWidth: embedded ? nil : 460, minHeight: embedded ? nil : 320,
               maxHeight: embedded ? .infinity : nil, alignment: .top)
        .onChange(of: draft.apiKey) { _, _ in validation = .idle }
        .onChange(of: draft.baseURL) { _, _ in validation = .idle }
        .confirmationDialog("Delete this account?",
                            isPresented: $showDeleteConfirmation,
                            titleVisibility: .visible) {
            Button("Delete Account", role: .destructive) { onDelete?() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("“\(initialName)” and its stored API key will be removed from this Mac. This can’t be undone.")
        }
    }

    /// Width of the right-aligned label column, sized to hold the longest label
    /// ("Description") so every field starts at the same x — the Mail look.
    private let labelColumnWidth: CGFloat = 84

    /// One Mail-style row: a right-aligned label paired with a left-aligned field.
    private func fieldRow<Content: View>(_ label: String,
                                         @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .frame(width: labelColumnWidth, alignment: .trailing)
                .foregroundStyle(.secondary)
            content()
        }
    }

    /// Bridges the optional `baseURL` to the text field: an empty field means
    /// "use the default", which we store as `nil` rather than an empty string.
    private var baseURLBinding: Binding<String> {
        Binding(
            get: { draft.baseURL ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                draft.baseURL = trimmed.isEmpty ? nil : trimmed
            }
        )
    }

    private var isValidated: Bool {
        if case .valid = validation { return true }
        return false
    }

    /// Whether the editor is modifying a saved account (vs. adding a new one); the
    /// Delete callback is supplied only in that case.
    private var isEditing: Bool { onDelete != nil }

    /// Org member emails for the picker, including any already-saved email that the
    /// org list might not return, sorted for a stable order.
    private var emailOptions: [String] {
        var emails = Set(orgUsers.map(\.email).filter { !$0.isEmpty })
        if let saved = draft.userEmail, !saved.isEmpty { emails.insert(saved) }
        return emails.sorted()
    }

    private func emailLabel(_ email: String) -> String {
        if let name = orgUsers.first(where: { $0.email == email })?.name, !name.isEmpty {
            return "\(name) · \(email)"
        }
        return email
    }

    private var validateDisabled: Bool {
        draft.apiKey.trimmingCharacters(in: .whitespaces).isEmpty || validation == .validating
    }

    @ViewBuilder
    private var validateButton: some View {
        // When Save is available it owns the default action (Return); otherwise Validate
        // is the primary call to action, so only one button claims the shortcut.
        if canSave {
            Button("Validate") { Task { await validate() } }
                .buttonStyle(.bordered)
                .disabled(validateDisabled)
        } else {
            Button("Validate") { Task { await validate() } }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(validateDisabled)
        }
    }

    /// Whether the draft has a non-empty user email. Required to save: the email
    /// identifies "you" for the My Pads/My Questions filters and the menu bar.
    private var hasEmail: Bool {
        draft.userEmail?.trimmingCharacters(in: .whitespaces).isEmpty == false
    }

    /// A saved account whose key and server URL are untouched can be re-saved without
    /// re-validating, so edits to the Description or email persist freely; a new account
    /// or a changed credential still requires a successful validation first. In every
    /// case a user email is required — a legacy account saved without one must be
    /// re-validated (which reveals the picker and auto-detects the email) before it
    /// can be saved again.
    private var canSave: Bool {
        guard hasEmail else { return false }
        return isValidated || (isEditing && draft.apiKey == initialAPIKey && draft.baseURL == initialBaseURL)
    }

    @ViewBuilder
    private var saveButton: some View {
        let save = {
            finalizeNameIfNeeded()
            onSave(draft)
        }
        if canSave {
            Button("Save", action: save)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        } else {
            Button("Save", action: save)
                .buttonStyle(.bordered)
                .disabled(true)
        }
    }

    private func finalizeNameIfNeeded() {
        if draft.name.trimmingCharacters(in: .whitespaces).isEmpty {
            if case .valid(let org) = validation {
                draft.name = org
            } else {
                draft.name = "Account"
            }
        }
    }

    @ViewBuilder
    private var validationBanner: some View {
        switch validation {
        case .idle, .valid:
            EmptyView()
        case .validating:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Validating API key…").foregroundStyle(.secondary)
            }
            .font(.callout)
        case .invalid(let message):
            Label(message, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red).font(.callout)
        }
    }

    private func validate() async {
        validation = .validating
        do {
            let client = CoderPadClient(apiKey: draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                                        baseURL: draft.resolvedBaseURL)
            let org = try await client.organization()
            orgUsers = org.users
            if draft.name.trimmingCharacters(in: .whitespaces).isEmpty {
                draft.name = org.organizationName
            }
            // Pre-select the signed-in user's email. The default /api/pads/ endpoint
            // is scoped to the API key owner, so the dominant owner email on their pads
            // is "you" — detect it directly rather than making the user pick. Fall back
            // to the single-user org case, then to the manual picker. This runs while
            // still in the validating state so the spinner covers the email retrieval.
            if draft.userEmail == nil {
                if let detected = await detectUserEmail(client: client) {
                    draft.userEmail = detected
                } else if org.users.count == 1 {
                    draft.userEmail = org.users.first?.email
                }
            }
            validation = .valid(org.organizationName)
        } catch {
            validation = .invalid(friendlyValidationMessage(for: error))
        }
    }

    /// Derives the signed-in user's email from their own pads. `/api/pads/` is scoped
    /// to the API key owner, so the most common owner email on the first page is "you".
    /// Returns nil if the user has no pads yet (e.g. a brand-new account), letting the
    /// caller fall back to the manual picker. Non-fatal: validation already succeeded.
    private func detectUserEmail(client: CoderPadClient) async -> String? {
        do {
            for try await page in client.listPadsIncrementally() {
                let emails = page.map(\.ownerEmail).filter { !$0.isEmpty }
                guard !emails.isEmpty else { return nil }
                let counts = Dictionary(emails.map { ($0, 1) }, uniquingKeysWith: +)
                return counts.max { $0.value < $1.value }?.key
            }
        } catch {
            // Ignore: the picker remains available as a fallback.
        }
        return nil
    }

    private func friendlyValidationMessage(for error: Error) -> String {
        if let api = error as? CoderPadError {
            if api.isUnauthorized {
                return "CoderPad rejected this key. Double-check that it's the right one and hasn't been revoked."
            }
            switch api {
            case .missingAPIKey:
                return "Paste your CoderPad API key above."
            case .http:
                return "CoderPad couldn't verify the key right now. Try again in a moment."
            case .decode:
                return "CoderPad returned something unexpected. Try again, and if it keeps happening, regenerate the key."
            }
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return "Couldn't reach CoderPad. Check your internet connection and try again."
        }
        return "Couldn't validate this key. Try again."
    }
}

/// A searchable replacement for a long `Picker` of organization members. Shows the
/// current selection as a button; tapping opens a popover with a search field that
/// filters the (potentially large) member list so you don't scroll a huge menu.
private struct OrgMemberPicker: View {
    @Binding var selection: String?
    let options: [String]
    let label: (String) -> String

    @State private var isPresented = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var filtered: [String] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return options }
        return options.filter { label($0).localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack {
                Text(selection.map(label) ?? "Unset")
                    .foregroundStyle(selection == nil ? .secondary : .primary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.bordered)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(spacing: 0) {
                TextField("Search members", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                    .padding(8)

                Divider()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        memberRow(email: nil, title: "Unset")
                        ForEach(filtered, id: \.self) { email in
                            memberRow(email: email, title: label(email))
                        }
                        if filtered.isEmpty {
                            Text("No members match “\(query)”")
                                .foregroundStyle(.secondary)
                                .font(.callout)
                                .padding(8)
                        }
                    }
                }
                .frame(maxHeight: 240)
            }
            .frame(width: 320)
            .onAppear { searchFocused = true }
        }
    }

    @ViewBuilder
    private func memberRow(email: String?, title: String) -> some View {
        let isSelected = email == selection
        Button {
            selection = email
            isPresented = false
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(email == nil ? .secondary : .primary)
                    .lineLimit(1)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.accentColor.opacity(0.12) : .clear)
    }
}

#Preview { SettingsView() }
