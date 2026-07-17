//
//  ContentView.swift
//  coderpad
//

import SwiftUI
import WhatsNewKit

enum AppSection: String, Hashable {
    case pads, questions, organization, quota, screen
}

extension AppSection {
    /// The top-to-bottom order of navigable top-level sections, computed from the
    /// shared account + quota stores. Single source of truth for both the sidebar's
    /// `sectionOrder` and the Go ▸ Next/Previous Section commands (`cycleSection`),
    /// so the two never disagree. Quota drops out on an unlimited single-account plan
    /// where its row is a non-navigable indicator (#306); Screen appears only when a
    /// Screen key is configured (#432/#442). Mirrors `quotaIsUnlimited` /
    /// `screenSectionAvailable` in ContentView+Sidebar.
    static var navigable: [AppSection] {
        let accounts = AccountsStore.shared
        let merged = accounts.isMergedView
        var order: [AppSection] = [.pads, .questions, .organization]

        let quotaUnlimited = !merged
            && (accounts.currentAccountID.map { QuotaCacheStore.shared.get($0)?.unlimited == true } ?? false)
        if !quotaUnlimited { order.append(.quota) }

        let screenAvailable = merged
            ? accounts.mergeableAccounts.contains { $0.makeScreenClient() != nil }
            : accounts.currentAccount?.makeScreenClient() != nil
        if screenAvailable { order.append(.screen) }

        return order
    }
}

struct ContentView: View {
    @State private var store = AccountsStore.shared
    @State private var nav = AppNavigation.shared
    @State private var directory = OrgDirectory()
    @State private var monitor = AccountHealthMonitor.shared
    @State private var network = NetworkMonitor.shared
    @State private var openPadURLDraft: String = ""
    @State private var showOpenPadURL = false
    @State private var showCommandPalette = false
    @Environment(\.openAppSettings) private var openSettings
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        presentedSheets(routing(windowContent))
            // WhatsNewKit auto-presents the current release's sheet once per version,
            // gating on the bundle version and recording it in the local store. The
            // store is plain UserDefaults so it persists on both the App Store and
            // Developer ID builds (the latter can't carry the iCloud KVS entitlement).
            .whatsNewSheet()
            .environment(
                \.whatsNew,
                WhatsNewEnvironment(
                    versionStore: UserDefaultsWhatsNewVersionStore(),
                    whatsNewCollection: [WhatsNewContent.current]
                )
            )
    }

    private var windowContent: some View {
        platformChrome(rootContent)
            .environment(\.orgDirectory, directory)
            // While offline the whole window goes read-only: editing controls read this
            // to disable themselves, and the menu commands read the focused-scene mirror
            // below so they match (#321).
            .environment(\.isReadOnly, network.isOffline)
            .focusedSceneValue(\.isReadOnly, network.isOffline)
    }

    @ViewBuilder
    private var rootContent: some View {
        if store.currentAccount == nil {
            noAccountView
                .frame(minHeight: 380)
                .frame(minWidth: noAccountMinimumWidth)
        } else if shouldUsePhoneLayout {
            #if os(iOS)
                PhoneContentView(directory: directory, monitor: monitor)
            #endif
        } else {
            MainSplit(
                section: $nav.section,
                directory: directory,
                monitor: monitor
            )
        }
    }

    @ViewBuilder
    private func platformChrome(_ content: some View) -> some View {
        // Keep the title bar standard so the system's own sidebar toggle and
        // View ▸ Show/Hide Sidebar command are present, and let MainSplit's
        // `.navigationTitle`/`.navigationSubtitle` read out the current section
        // ("Pads", "Questions", "All accounts") like Mail's mailbox title. Only the
        // hairline separator under the unified toolbar is dropped, for the seamless
        // look — the title itself stays visible.
        #if os(macOS)
            content.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        #else
            content
        #endif
    }

    private var noAccountMinimumWidth: CGFloat? {
        #if os(macOS)
            520
        #else
            nil
        #endif
    }

    private var shouldUsePhoneLayout: Bool {
        #if os(iOS)
            horizontalSizeClass == .compact
        #else
            false
        #endif
    }

    private func routing(_ content: some View) -> some View {
        content
            // Focused-window scoped: these are process-wide broadcasts, and with
            // several main windows open each used to present its own copy of the
            // sheet/palette at once (#906).
            .onFocusedWindowRequest({ AppRouter.openPadByURLRequests }) {
                showOpenPadURL = true
            }
            .onFocusedWindowRequest({ AppRouter.commandPaletteRequests }) {
                showCommandPalette = true
            }
            // The "Open Pad by ID" intent routes through durable AppNavigation state so a
            // cold-launch request isn't dropped: consume whatever is already pending on
            // appear, and react to any value set afterwards.
            .task { scheduleConsumeOpenPadID() }
            .onChange(of: nav.openPadID) { _, _ in scheduleConsumeOpenPadID() }
    }

    private func presentedSheets(_ content: some View) -> some View {
        content
            .sheet(isPresented: $showOpenPadURL) {
                OpenPadURLSheet(
                    urlString: $openPadURLDraft,
                    onSubmit: { url in
                        BrowserSettings.openExternally(url)
                        openPadURLDraft = ""
                        showOpenPadURL = false
                    },
                    onCancel: {
                        openPadURLDraft = ""
                        showOpenPadURL = false
                    }
                )
            }
            .sheet(isPresented: $showCommandPalette) {
                CoderPadCommandPalette()
            }
    }

    private func scheduleConsumeOpenPadID() {
        DispatchQueue.main.async { consumeOpenPadID() }
    }

    /// Opens any pad id queued by the "Open Pad by ID" intent, then clears it so it
    /// isn't reopened on the next change. Re-validates the id here as well as in the
    /// intent so a queued value can never rewrite the URL it's interpolated into (#778).
    private func consumeOpenPadID() {
        guard let raw = nav.openPadID else { return }

        nav.openPadID = nil
        guard let id = PadIDValidation.normalize(raw) else { return }

        BrowserSettings.openExternally(padURL(for: id))
    }

    /// The web URL for a pad id queued by ID-based routing (Spotlight, the Open Pad
    /// intent, notifications, coderpad://pad/...). Prefers the cached pad's own URL
    /// from whichever account holds it, then that account's server, then the current
    /// account's - never a hardcoded host, which sent self-hosted and regional
    /// accounts' pads to app.coderpad.io where they don't exist (#731).
    private func padURL(for id: String) -> URL {
        for account in store.accounts {
            guard let pad = PadsCacheStore.shared.get(account.id).first(where: { $0.id == id })
            else { continue }

            return pad.webURL(fallbackBase: account.resolvedBaseURL)
        }
        let base = store.currentAccount?.resolvedBaseURL ?? CoderPadClient.defaultBaseURL
        return base.appending(path: id)
    }

    /// Starts account setup on the canonical Settings > Accounts inline editor, the
    /// same route the menu bar's "Add Account" uses (#556). Setting the tab and the
    /// add flag before Settings opens lets the editor land on a fresh draft rather
    /// than a generic tab.
    private func startAddingAccount() {
        SettingsNavigation.shared.selectedTab = .accounts
        SettingsNavigation.shared.startAddingAccount = true
        openSettings()
    }

    @ViewBuilder
    private var noAccountView: some View {
        if store.accounts.isEmpty {
            // First run: a small onboarding surface rather than a bare empty state.
            // Explains what PadBuddy needs, sends the primary action into the same
            // Settings > Accounts editor the rest of the app uses, and offers the
            // "Get an API key" link so users can find the key before setup (#556).
            ContentUnavailableView {
                Label("Welcome to PadBuddy", systemImage: "doc.text.magnifyingglass")
            } description: {
                Text("""
                PadBuddy connects to your CoderPad account with an API key, then keeps \
                your pads and questions a click away. Add an account to get started.
                """)
            } actions: {
                Button("Add Account") { startAddingAccount() }
                    .buttonStyle(.glassProminent)
                GetAPIKeyLink()
            }
        } else {
            ContentUnavailableView {
                Label("No account selected", systemImage: "person.crop.circle.badge.questionmark")
            } description: {
                Text("Choose one of your saved accounts in Settings.")
            } actions: {
                Button("Open Settings") { openSettings() }
                    .buttonStyle(.glassProminent)
            }
        }
    }
}
