//
//  ContentView.swift
//  coderpad
//

// swiftlint:disable file_length

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
        if !quotaUnlimited {
            order.append(.quota)
        }

        let screenAvailable = merged
            ? accounts.mergeableAccounts.contains(where: \.hasScreenAccess)
            : accounts.currentAccount?.hasScreenAccess == true
        if screenAvailable {
            order.append(.screen)
        }

        return order
    }
}

struct PadBuddyWelcomeView: View {
    let onAddAccount: () -> Void

    var body: some View {
        #if os(visionOS)
            spatialWelcome
        #else
            GeometryReader { proxy in
                let isCompact = proxy.size.width < 560

                ScrollView {
                    VStack(spacing: isCompact ? 18 : 24) {
                        welcomeHeader(isCompact: isCompact)
                        welcomeActions(isCompact: isCompact)
                    }
                    .padding(.horizontal, isCompact ? 28 : 32)
                    .padding(.vertical, isCompact ? 24 : 44)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height)
                }
                .scrollIndicators(.hidden)
                .background(WelcomeBackdrop())
            }
        #endif
    }

    #if os(visionOS)
        /// A bounded ornament-like card reads as content in a spatial window instead of
        /// turning the entire resizable glass surface into an oversized empty panel.
        private var spatialWelcome: some View {
            VStack(spacing: 24) {
                Image(systemName: "curlybraces.square")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                welcomeHeader(isCompact: false)
                Text("Connect a CoderPad account to browse pads, questions, and interviews.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                welcomeActions(isCompact: false)
            }
            .padding(40)
            .frame(maxWidth: 520)
            .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    #endif

    private func welcomeHeader(isCompact: Bool) -> some View {
        Text("Welcome to PadBuddy")
            .font(isCompact ? .title.bold() : .largeTitle.bold())
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .accessibilityAddTraits(.isHeader)
    }

    private func welcomeActions(isCompact: Bool) -> some View {
        VStack(spacing: isCompact ? 14 : 16) {
            Button {
                onAddAccount()
            } label: {
                Label("Add CoderPad Account", systemImage: "person.crop.circle.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .prominentActionButtonStyle()
            .keyboardShortcut(.defaultAction)
            .frame(maxWidth: 340)
        }
    }
}

private struct WelcomeBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    platformBackgroundColor,
                    Color.accentColor.opacity(0.10),
                    Color.teal.opacity(0.08),
                    platformBackgroundColor
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            WelcomeGrid()
                .stroke(Color.primary.opacity(0.045), lineWidth: 1)
                .mask(
                    LinearGradient(colors: [.clear, .black, .clear],
                                   startPoint: .top,
                                   endPoint: .bottom)
                )
        }
        .ignoresSafeArea()
    }

    private var platformBackgroundColor: Color {
        #if os(macOS)
            Color(nsColor: .windowBackgroundColor)
        #else
            Color(uiColor: .systemBackground)
        #endif
    }
}

private struct WelcomeGrid: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        let step: CGFloat = 34

        var diagonalX = rect.minX - rect.height
        while diagonalX <= rect.maxX + rect.height {
            path.move(to: CGPoint(x: diagonalX, y: rect.minY))
            path.addLine(to: CGPoint(x: diagonalX + rect.height, y: rect.maxY))
            diagonalX += step
        }

        var horizontalY = rect.minY
        while horizontalY <= rect.maxY {
            path.move(to: CGPoint(x: rect.minX, y: horizontalY))
            path.addLine(to: CGPoint(x: rect.maxX, y: horizontalY))
            horizontalY += step
        }

        return path
    }
}

struct ContentView: View { // swiftlint:disable:this type_body_length
    @State private var store = AccountsStore.shared
    @State private var nav = AppNavigation.shared
    /// This window's published navigation state and merged-view routing. Owned per
    /// scene (not process-wide singletons) so other main windows can't overwrite this
    /// window's counts, Screen drill-down, or merged detail routing (#887, #888,
    /// #908, #911); injected into the environment for every pane below.
    @State private var windowNav = WindowNavigation()
    @State private var mergedRouting = MergedRouting()
    @State private var directory = OrgDirectory()
    @State private var monitor = AccountHealthMonitor.shared
    @State private var network = NetworkMonitor.shared
    @State private var openPadURLDraft: String = ""
    @State private var showOpenPadURL = false
    @State private var showCommandPalette = false
    // Always mounted for the scene, including welcome and no-account shells, so a
    // reset clears scene storage before any account content is mounted again (#5151).
    @SceneStorage("section.window") private var resetPersistedWindowSection = ""
    @SceneStorage("pads.merged.selectedPad") private var resetPersistedSelectedPad = ""
    @SceneStorage("pads.merged.selectedPad.endpoint") private var resetPersistedSelectedPadEndpoint = ""
    @SceneStorage("pads.merged.topRow") private var resetPersistedPadTopRow = ""
    @SceneStorage("pads.merged.topRow.endpoint") private var resetPersistedPadTopRowEndpoint = ""
    @SceneStorage("pads.merged.liveFilter") private var resetPersistedPadLiveFilter = ""
    @SceneStorage("questions.merged.selectedRow") private var resetPersistedSelectedQuestion = ""
    @SceneStorage("questions.merged.selectedRow.endpoint") private var resetPersistedSelectedQuestionEndpoint = ""
    @SceneStorage("questions.merged.topRow") private var resetPersistedQuestionTopRow = ""
    @SceneStorage("questions.merged.topRow.endpoint") private var resetPersistedQuestionTopRowEndpoint = ""
    @SceneStorage("questions.merged.liveFilter") private var resetPersistedQuestionLiveFilter = ""
    /// Focus-gated copy of a process-wide unsupported deep link so only the frontmost
    /// window presents the alert (#4662).
    @State private var presentedUnsupportedDeepLink: URL?
    /// Focus-gated copy of a browser-launch failure so only the frontmost window
    /// presents the recovery alert (#4664).
    @State private var presentedBrowserOpenFailure: String?
    /// Identity for this mounted window's Find publisher. Its search closure must
    /// not compare equal to one retained from a replaced ContentView (#2733).
    @State var findActionPublisherID = UUID()
    private let whatsNewEnvironment = WhatsNewEnvironment(
        versionStore: UserDefaultsWhatsNewVersionStore(),
        whatsNewCollection: [WhatsNewContent.current]
    )
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
            .environment(\.whatsNew, whatsNewEnvironment)
            .environment(windowNav)
            .environment(mergedRouting)
            .onReceive(NotificationCenter.default.publisher(for: .appStateRestorationDidReset)) { _ in
                clearSceneRestorationState()
            }
            .alert("Cannot Open Link", isPresented: unsupportedDeepLinkPresentation) {
                Button("Show Pads") {
                    presentedUnsupportedDeepLink = nil
                    nav.show(.pads)
                }
                Button("Dismiss", role: .cancel) { presentedUnsupportedDeepLink = nil }
            } message: {
                Text("This link is not supported. You can return to Pads and find the item manually.")
            }
            .favoriteLimitAlert()
            .alert("Could Not Open Browser", isPresented: browserOpenFailurePresentation) {
                Button("OK", role: .cancel) { presentedBrowserOpenFailure = nil }
            } message: {
                Text(presentedBrowserOpenFailure ?? "The link could not be opened.")
            }
    }

    private func clearSceneRestorationState() {
        resetPersistedWindowSection = ""
        resetPersistedSelectedPad = ""
        resetPersistedSelectedPadEndpoint = ""
        resetPersistedPadTopRow = ""
        resetPersistedPadTopRowEndpoint = ""
        resetPersistedPadLiveFilter = ""
        resetPersistedSelectedQuestion = ""
        resetPersistedSelectedQuestionEndpoint = ""
        resetPersistedQuestionTopRow = ""
        resetPersistedQuestionTopRowEndpoint = ""
        resetPersistedQuestionLiveFilter = ""
    }

    private var unsupportedDeepLinkPresentation: Binding<Bool> {
        Binding(
            get: { presentedUnsupportedDeepLink != nil },
            set: {
                if !$0 {
                    presentedUnsupportedDeepLink = nil
                }
            }
        )
    }

    private var browserOpenFailurePresentation: Binding<Bool> {
        Binding(
            get: { presentedBrowserOpenFailure != nil },
            set: {
                if !$0 {
                    presentedBrowserOpenFailure = nil
                }
            }
        )
    }

    private var windowContent: some View {
        platformChrome(rootContent)
            .environment(\.orgDirectory, directory)
            // While offline the whole window goes read-only: editing controls read this
            // to disable themselves, and the menu commands read the focused-scene mirror
            // below so they match (#321).
            .environment(\.isReadOnly, isServiceReadOnly)
            .focusedSceneValue(\.isReadOnly, isServiceReadOnly)
    }

    private var isServiceReadOnly: Bool {
        if network.isOffline {
            return true
        }
        if store.isMergedView {
            let ids = store.mergeableAccounts.map(\.id)
            return !ids.isEmpty && ids.allSatisfy(monitor.isUnavailable)
        }
        return store.currentAccountID.map(monitor.isUnavailable) ?? false
    }

    @ViewBuilder
    private var rootContent: some View {
        if store.currentAccount == nil || WelcomePresentationPolicy.shouldShow(
            hasAccounts: !store.accounts.isEmpty,
            arguments: ProcessInfo.processInfo.arguments
        ) {
            noAccountView
                .frame(minHeight: 380)
                .frame(minWidth: noAccountMinimumWidth)
        } else if shouldUsePhoneLayout {
            #if os(iOS)
                PhoneContentView(directory: directory, monitor: monitor)
            #endif
        } else {
            MainSplit(
                section: $windowNav.section,
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
            .onFocusedWindowRequest(.openPadByURL) {
                AppRouter.openPadByURLRequests
            } perform: {
                showOpenPadURL = true
            }
            .onFocusedWindowRequest(.commandPalette) {
                AppRouter.commandPaletteRequests
            } perform: {
                showCommandPalette = true
            }
            // The "Open Pad by ID" intent routes through durable AppNavigation state so a
            // cold-launch request isn't dropped: consume whatever is already pending on
            // appear, and react to any value set afterwards.
            // Focus-gated like the other mailbox requests: every window used to
            // schedule consumption, so a background window could clear the Open
            // Pad intent and fire the browser open instead of the frontmost one
            // (#1671).
            .consumesWindowRequest(nav.openPadRequest) { consumeOpenPadRequest() }
            // Section switches are per-window (#907): the mailbox carries the request
            // and only this window applies it while focused, so a menu command, deep
            // link, or sidebar tap can't retarget every other open window.
            .consumesWindowRequest(nav.sectionRequest) { consumeSectionRequest() }
            .consumesWindowRequest(nav.sectionCycleRequest) { consumeSectionCycle() }
            // Unsupported deep links and browser-open failures are process-wide; claim
            // them only in the focused window so every open ContentView does not present
            // the same alert (#4662, #4664).
            .consumesWindowRequest(nav.unsupportedDeepLink) {
                guard let url = nav.unsupportedDeepLink else { return }

                presentedUnsupportedDeepLink = url
                nav.unsupportedDeepLink = nil
            }
            .consumesWindowRequest(nav.browserOpenFailure) {
                guard let message = nav.browserOpenFailure else { return }

                presentedBrowserOpenFailure = message
                nav.browserOpenFailure = nil
            }
            .onAppear {
                let arguments = ProcessInfo.processInfo.arguments
                if coderpadIsUITesting,
                   let index = arguments.firstIndex(of: "-uiTestingSection"), index + 1 < arguments.count,
                   let section = AppSection(rawValue: arguments[index + 1]) {
                    windowNav.section = section
                }
            }
    }

    private func consumeSectionRequest() {
        guard let section = nav.sectionRequest else { return }

        nav.sectionRequest = nil
        windowNav.section = section
    }

    /// Steps this window's section through the navigable order, wrapping at the
    /// ends - resolved here (not at the menu command) so the step is relative to
    /// this window's own section rather than a process-wide one (#907).
    private func consumeSectionCycle() {
        guard let request = nav.sectionCycleRequest else { return }

        nav.sectionCycleRequest = nil
        let order = AppSection.navigable
        guard !order.isEmpty else { return }

        let index = order.firstIndex(of: windowNav.section) ?? 0
        let count = order.count
        windowNav.section = order[((index + request.delta) % count + count) % count]
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

    /// Opens any pad id queued by the "Open Pad by ID" intent, then clears it so it
    /// intent so a queued value can never rewrite the URL it's interpolated into (#778).
    /// intent so a queued value can never rewrite the URL it is interpolated into (#778).
    private func consumeOpenPadRequest() {
        guard let request = nav.takeOpenPadRequest() else { return }
        guard let id = PadIDValidation.normalize(request.id) else { return }
        guard let url = padURL(for: id, owningAccountID: request.accountID) else { return }

        if let accountID = request.accountID
            ?? store.accounts.first(where: { PadsCacheStore.shared.get($0.id).contains { $0.id == id } })?.id {
            PadOpenedStore.shared.record(id, account: accountID)
        }
        BrowserSettings.openExternally(url)
    }

    /// The web URL for a pad id queued by ID-based routing (Spotlight, the Open Pad
    /// intent, notifications, com.adamdangoor.padbuddy://pad/...). A request that names its owning
    /// account (a namespaced Spotlight result) resolves against that account first —
    /// slugs collide across custom servers, so a cache scan by bare id could pick
    /// another server's same-slug pad (#759). Otherwise prefers the cached pad's own
    /// URL from whichever account holds it, then that account's server, then the
    /// current account's - never a hardcoded host, which sent self-hosted and regional
    /// accounts' pads to app.coderpad.io where they don't exist (#731).
    private func padURL(for id: String, owningAccountID: UUID?) -> URL? {
        if let owningAccountID,
           let account = store.accounts.first(where: { $0.id == owningAccountID }) {
            if let pad = PadsCacheStore.shared.get(account.id).first(where: { $0.id == id }) {
                return pad.webURL(fallbackBase: account.resolvedBaseURL)
            }
            return Pad.fallbackWebURL(id: id, base: account.resolvedBaseURL)
        }
        // A bare slug resolves from the caches only when exactly one account holds
        // it, or via the current account's own copy: duplicate slugs on custom
        // servers must not open whichever account happened to be listed first (#1672).
        //
        // One pass per account, keeping the match as it goes. This used to scan every
        // account's whole pad list to count the holders, then scan the winner's list
        // again for the pad, then possibly scan the current account's — two or three
        // full O(accounts x pads) sweeps per id-based navigation, and `get` can reach
        // disk (#2474).
        var holders: [(account: Account, pad: Pad)] = []
        for account in store.accounts {
            guard let pad = PadsCacheStore.shared.get(account.id).first(where: { $0.id == id }) else { continue }

            holders.append((account, pad))
        }
        if holders.count == 1, let match = holders.first {
            return match.pad.webURL(fallbackBase: match.account.resolvedBaseURL)
        }
        if let current = store.currentAccount,
           let match = holders.first(where: { $0.account.id == current.id }) {
            return match.pad.webURL(fallbackBase: current.resolvedBaseURL)
        }
        let base = store.currentAccount?.resolvedBaseURL ?? CoderPadClient.defaultBaseURL
        return Pad.fallbackWebURL(id: id, base: base)
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
        if WelcomePresentationPolicy.shouldShow(
            hasAccounts: !store.accounts.isEmpty,
            arguments: ProcessInfo.processInfo.arguments
        ) {
            PadBuddyWelcomeView(onAddAccount: startAddingAccount)
        } else {
            ContentUnavailableView {
                Label("No account selected", systemImage: "person.crop.circle.badge.questionmark")
            } description: {
                Text("Choose one of your saved accounts in Settings.")
            } actions: {
                Button("Open Settings") { openSettings() }
                    .prominentActionButtonStyle()
            }
        }
    }
}
