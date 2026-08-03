//
//  SettingsView.swift
//  coderpad
//

import SwiftUI

/// The tabs in the Settings window, used to drive `SettingsView`'s selection so
/// callers can open Settings on a specific tab (e.g. the unauthorized banner jumps
/// straight to Accounts).
enum SettingsTab: Hashable {
    case general
    case accounts
    case browser
    case menuBar
    case mcp
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
    /// When true, Settings switches to the Accounts tab and immediately opens the
    /// "add account" editor, then clears the flag. Lets the menu bar's "Add Account…"
    /// jump straight into adding rather than landing on a generic Settings tab (#452).
    var startAddingAccount = false
    private init() {}
}

struct SettingsView: View {
    nonisolated static func addAccountRequestNeedsDiscardConfirmation(savedAccountEditDirty: Bool) -> Bool {
        savedAccountEditDirty
    }

    #if !os(macOS)
        @Environment(\.horizontalSizeClass) var horizontalSizeClass
    #endif

    @State var store = AccountsStore.shared
    @State var navigation = SettingsNavigation.shared
    @State var preferenceSync = PreferenceCloudSync.shared
    @State var selectedAccountID: UUID?
    /// A not-yet-saved account being added. While non-nil, the detail pane shows the
    /// editor for it and the sidebar selection is cleared — mirroring Mail, where the
    /// `+` button reveals an inline setup pane rather than a modal sheet.
    @State var addingAccount: Account?
    /// The account the sidebar minus button is about to remove; non-nil presents the
    /// delete confirmation (#772), mirroring the editor's own delete button.
    @State var accountPendingRemoval: UUID?
    @State var accountAddUnavailableReason: String?
    @State var savedAccountEditDirty = false
    @State var confirmDiscardForAdd = false
    @State var network = NetworkMonitor.shared
    #if os(macOS)
        /// The browser list and system-default name, scanned once per appearance
        /// rather than rebuilt inside the picker's body (#2447).
        @State var installedBrowsers: [InstalledBrowser] = []
        @State var systemDefaultBrowserName: String?
    #endif

    // Browser and menu-bar preferences live in UserDefaults under the keys defined
    // in `BrowserSettings.Key`; `@AppStorage` reads/writes those same keys so the
    // app-wide static getters on `BrowserSettings` stay in sync.
    @AppStorage(BrowserSettings.Key.defaultBrowserBundleID) var defaultBrowserBundleID: String?
    @AppStorage(BrowserSettings.Key.openInBackground) var openInBackground = false
    @AppStorage(SettingsPreferenceRecovery.menuBarTopNKey) var menuBarTopN = 3
    @AppStorage("menuBarStartedOnly") var menuBarStartedOnly = false

    /// Whether the user has opted into the local MCP server integration. Gates both the
    /// in-app setup instructions and serving itself: a `--mcp` launch refuses to serve
    /// while this is off (#811), so already-installed assistants lose access too.
    @AppStorage(MCPServer.enabledDefaultsKey) var mcpServerEnabled = false
    /// A requested server state remains here until the user confirms its effect on
    /// already-installed assistants (#1620).
    @State var pendingMCPServerEnabled: Bool?

    /// Accounts for which MCP writes are explicitly authorized (#1622).
    @State var mcpWritableAccountIDs = Set<UUID>()

    /// Tails the headless server's activity log for the MCP pane's status area (#523).
    @State var mcpActivity = MCPActivityStore()
    @State var mcpHealthStatus: MCPHealthStatus = .idle
    @AppStorage(MCPActivityPresentation.detailsDefaultsKey) var mcpActivityDetailsVisible = false
    @State var showClearMCPActivityConfirmation = false

    // General preferences, backed by the keys in `GeneralSettings.Key`.
    @AppStorage(GeneralSettings.Key.appearance) var appearance: AppAppearance = .system
    @AppStorage(GeneralSettings.Key.presence) var presence: AppPresence = .dockAndMenuBar
    @AppStorage(GeneralSettings.Key.spotlightIndexing) var spotlightIndexing = false
    @AppStorage(GeneralSettings.Key.notifyOnPadUpdates) var notifyOnPadUpdates = false
    @State var notificationPermissionDenied = false
    @State var notificationTestMessage: String?
    @State var notificationPreviewAccountID: UUID?
    @State var confirmResetRestoredState = false
    @State var restoredStateResetMessage: String?
    @AppStorage(GeneralSettings.Key.hidePadTitlesInNotifications) var hidePadTitlesInNotifications = false
    @AppStorage(GeneralSettings.Key.includeIdentitiesInPadExports) var includeIdentitiesInPadExports = false
    @AppStorage(GeneralSettings.Key.showAccountEmailsInSectionHeaders) var showAccountEmailsInSectionHeaders = false
    @AppStorage(DockBadgeController.Key.scope) var dockBadgeScope: DockBadgeScope = .allAccounts
    @State var accountsStore = AccountsStore.shared

    // Launch-at-login mirrors the live `SMAppService` state rather than UserDefaults,
    // so it's plain view state kept in sync on appear and after each toggle.
    @State var launchAtLogin = LoginItem.isEnabled
    @State var loginItemError: String?

    var body: some View {
        settingsRoot
    }

    private var settingsRoot: some View {
        settingsNavigationRoot
            .alert(item: .init(
                get: { preferenceSync.validationIssue },
                set: {
                    if $0 == nil {
                        preferenceSync.dismissValidationIssue()
                    }
                }
            )) { issue in
                Alert(
                    title: Text("Invalid synced preference"),
                    message: Text("PadBuddy rejected an invalid value for \(issue.settingName). "
                        + "Review that setting to choose a valid value."),
                    primaryButton: .default(Text("Review Setting")) {
                        navigation.selectedTab = issue.destination
                    },
                    secondaryButton: .cancel()
                )
            }
            .alert(
                "Cannot Add Account",
                isPresented: .init(
                    get: { accountAddUnavailableReason != nil },
                    set: {
                        if !$0 {
                            accountAddUnavailableReason = nil
                        }
                    }
                )
            ) {
                if store.persistenceFailed {
                    Button("Retry Saving Accounts") {
                        accountAddUnavailableReason = nil
                        store.retryPersistence()
                    }
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text(accountAddUnavailableReason ?? "")
            }
            .alert("Discard Account Changes?", isPresented: $confirmDiscardForAdd) {
                Button("Keep Editing", role: .cancel) {}
                Button("Discard and Add Account", role: .destructive) {
                    savedAccountEditDirty = false
                    beginAddingAccount()
                }
            } message: {
                Text("The current account has changes that cannot be saved yet.")
            }
    }

    private var settingsNavigationRoot: some View {
        settingsTabView
        // macOS window sizing only; the iPad Settings sheet sizes itself.
        #if os(macOS)
        .frame(minWidth: 620, minHeight: 440)
        #endif
        // A caller (e.g. the unauthorized banner) can request the editor for a
        // specific account; honor it both when Settings first appears and while it's
        // already open.
        .onAppear {
            openPendingEdit(navigation.accountToEdit)
            startPendingAddAccount()
        }
        .onChange(of: navigation.accountToEdit) { _, id in openPendingEdit(id) }
        .onChange(of: navigation.startAddingAccount) { _, flag in
            if flag {
                startPendingAddAccount()
            }
        }
    }

    private var settingsTabView: some View {
        TabView(selection: $navigation.selectedTab) {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            accountsTab
                .tabItem { Label("Accounts", systemImage: "person.crop.circle") }
                .tag(SettingsTab.accounts)
            // Browser app selection, the menu-bar extra, and the MCP Server are macOS-only,
            // so these tabs do not appear on iPad.
            #if os(macOS)
                browserTab
                    .tabItem { Label("Browser", systemImage: "safari") }
                    .tag(SettingsTab.browser)
                // Always present so the Settings layout doesn't shift as the menu-bar icon
                // is toggled (#608); the tab explains and disables itself in Dock-only mode.
                menuBarTab
                    .tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }
                    .tag(SettingsTab.menuBar)
                mcpTab
                    .tabItem { Label("MCP Server", systemImage: "terminal") }
                    .tag(SettingsTab.mcp)
            #endif
        }
    }

    /// Bridges the stored `AppAppearance` preference to the `ColorScheme?` that
    /// buddy-kit's shared `AppearancePicker` binds to. `AppAppearance` is kept as the
    /// persisted form (and drives `preferredColorScheme`); the picker just reads/writes
    /// its color scheme, mapping nil back to `.system`.
    var appearanceSchemeBinding: Binding<ColorScheme?> {
        Binding(
            get: { appearance.colorScheme },
            set: { scheme in
                switch scheme {
                case .light: appearance = .light
                case .dark: appearance = .dark
                default: appearance = .system
                }
            }
        )
    }

    /// Reveal a requested account in the Accounts tab, switching tabs and selecting
    /// the row so its inline editor appears, then clearing the request so it fires
    /// only once.
    private func openPendingEdit(_ id: UUID?) {
        guard let id else { return }
        guard store.accounts.contains(where: { $0.id == id }) else {
            // The requested account is gone (removed before Settings opened):
            // consume the request instead of leaving it pending to fire against
            // an unrelated future state (#1614).
            navigation.accountToEdit = nil
            return
        }

        navigation.selectedTab = .accounts
        guard addingAccount == nil else {
            navigation.accountToEdit = nil
            return
        }

        addingAccount = nil
        selectedAccountID = id
        navigation.accountToEdit = nil
    }

    /// Switch to the Accounts tab and open a fresh account editor when a caller (the
    /// menu bar's "Add Account…") has requested it, then clear the flag so it fires
    /// once (#452).
    private func startPendingAddAccount() {
        guard navigation.startAddingAccount else { return }

        navigation.selectedTab = .accounts
        navigation.startAddingAccount = false
        guard !Self.addAccountRequestNeedsDiscardConfirmation(savedAccountEditDirty: savedAccountEditDirty) else {
            confirmDiscardForAdd = true
            return
        }

        beginAddingAccount()
    }

    func beginAddingAccount() {
        guard addingAccount == nil else { return }

        if let reason = Self.accountAddUnavailableReason(
            isOffline: network.isOffline,
            persistenceFailed: store.persistenceFailed
        ) {
            accountAddUnavailableReason = reason
            return
        }

        accountAddUnavailableReason = nil
        selectedAccountID = nil
        addingAccount = Account(name: "", apiKey: "")
    }

    nonisolated static func accountAddUnavailableReason(
        isOffline: Bool, persistenceFailed: Bool
    ) -> String? {
        if persistenceFailed {
            return String(localized: """
            Account changes are not being saved to the Keychain. Retry saving before adding another account.
            """)
        }
        if isOffline {
            return String(localized: """
            Connect to the internet before adding an account so its API key and organization can be verified.
            """)
        }
        return nil
    }

    /// Keep the detail pane attached to a real account when another window or a
    /// synchronized store update removes the selected row (#2805).
    func repairAccountSelection() {
        guard addingAccount == nil else { return }

        selectedAccountID = Self.recoveredAccountSelection(
            selected: selectedAccountID,
            current: store.currentAccountID,
            available: store.accounts.map(\.id)
        )
    }

    static func recoveredAccountSelection(selected: UUID?, current: UUID?, available: [UUID]) -> UUID? {
        if let selected, available.contains(selected) {
            return selected
        }
        if let current, available.contains(current) {
            return current
        }
        return available.first
    }
}

nonisolated struct MCPServerPreferenceChange: Equatable {
    let enabled: Bool

    func confirmed(allowWrites: Bool) -> (enabled: Bool, allowWrites: Bool) {
        (enabled, enabled ? allowWrites : false)
    }
}

#Preview { SettingsView() }
