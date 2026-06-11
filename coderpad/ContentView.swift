//
//  ContentView.swift
//  coderpad
//

import AppKit
import SwiftUI

enum AppSection: String, Hashable {
    case pads, questions, organization, quota
}

/// Strips the chrome Mail also omits: the window title (otherwise shown big at
/// the top of the sidebar) and the hairline separator under the unified toolbar.
private struct WindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ChromeView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ChromeView)?.applyChrome()
    }

    /// Applies the chrome in `viewDidMoveToWindow`, when the window is guaranteed
    /// to exist — and again on every SwiftUI update, since toolbar changes can
    /// otherwise reinstate the separator.
    final class ChromeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyChrome()
        }

        func applyChrome() {
            guard let window else { return }
            window.titleVisibility = .hidden
            window.titlebarSeparatorStyle = .none
        }
    }
}

struct ContentView: View {
    @State private var store = AccountsStore.shared
    @State private var nav = AppNavigation.shared
    @State private var showSettings = false
    @State private var addingAccount: Account?
    @State private var directory = OrgDirectory()
    @State private var monitor = AccountHealthMonitor.shared
    @State private var openPadURLDraft: String = ""
    @State private var showOpenPadURL = false
    @State private var showWhatsNew = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if store.currentAccount == nil {
                noAccountView
                    .frame(minWidth: 520, minHeight: 380)
            } else {
                MainSplit(
                    section: $nav.section,
                    showSettings: $showSettings,
                    directory: directory,
                    monitor: monitor
                )
            }
        }

        .background(WindowChromeConfigurator())
        .environment(\.openSettings, { showSettings = true })
        .environment(\.orgDirectory, directory)
        .onReceive(NotificationCenter.default.publisher(for: .openPadByURLRequested)) { _ in
            showOpenPadURL = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openPadIDRequested)) { note in
            if let id = note.object as? String,
               let url = URL(string: "https://app.coderpad.io/\(id)") {
                openWindow(id: "pad-browser", value: url)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsRequested)) { _ in
            showSettings = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openPadInBrowserRequested)) { note in
            if let url = note.object as? URL {
                openWindow(id: "pad-browser", value: url)
            }
        }
        .sheet(isPresented: $showOpenPadURL) {
            OpenPadURLSheet(
                urlString: $openPadURLDraft,
                onSubmit: { url in
                    openWindow(id: "pad-browser", value: url)
                    openPadURLDraft = ""
                    showOpenPadURL = false
                },
                onCancel: {
                    openPadURLDraft = ""
                    showOpenPadURL = false
                }
            )
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showSettings = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewSheet(release: WhatsNew.current) { showWhatsNew = false }
        }
        .sheet(item: $addingAccount) { account in
            AccountEditor(initial: account) { saved in
                store.add(saved)
                addingAccount = nil
            } onCancel: {
                addingAccount = nil
            }
        }
        .task {
            if WhatsNew.shouldShow() { showWhatsNew = true }
        }
    }



    @ViewBuilder
    private var noAccountView: some View {
        if store.accounts.isEmpty {
            ContentUnavailableView {
                Label("Welcome to CoderPad", systemImage: "doc.text.magnifyingglass")
            } actions: {
                Button("Add Account") { addingAccount = Account(name: "", apiKey: "") }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            ContentUnavailableView {
                Label("No account selected", systemImage: "person.crop.circle.badge.questionmark")
            } description: {
                Text("Choose one of your saved accounts in Settings.")
            } actions: {
                Button("Open Settings") { showSettings = true }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

struct WhatsNewRelease {
    let version: String
    let highlights: [(symbol: String, title: String, body: String)]
}

enum WhatsNew {
    static let current = WhatsNewRelease(
        version: "1.0",
        highlights: [
            ("magnifyingglass", "Search across the sidebar",
             "Type in the new sidebar search to jump straight into Pads or Questions."),
            ("person.crop.circle.badge.plus", "Accounts like Mail",
             "The Add Account flow auto-fills the name from your org and uses the +/− button set."),
            ("bolt.horizontal", "Faster section switching",
             "Pads and Questions are cached per account, so switching sections shows your last data instantly while a background reload runs."),
            ("keyboard", "More shortcuts",
             "⌘⇧N New Question, ⌘⌥C Copy Pad URL, ⌘↩ Open Pad in Browser."),
        ]
    )

    private static let key = "lastSeenWhatsNewVersion"

    static func shouldShow() -> Bool {
        let last = UserDefaults.standard.string(forKey: key)
        return last != current.version
    }

    static func markSeen() {
        UserDefaults.standard.set(current.version, forKey: key)
    }
}

struct WhatsNewSheet: View {
    let release: WhatsNewRelease
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("What's New in CoderPad").font(.title2.bold())
                Text("Version \(release.version)")
                    .font(.callout).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 14) {
                ForEach(0..<release.highlights.count, id: \.self) { i in
                    let item = release.highlights[i]
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: item.symbol)
                            .font(.title2)
                            .foregroundStyle(.tint)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.callout.weight(.semibold))
                            Text(item.body).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Continue") {
                    WhatsNew.markSeen()
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
        .frame(minWidth: 460)
    }
}

struct OpenPadURLSheet: View {
    @Binding var urlString: String
    let onSubmit: (URL) -> Void
    let onCancel: () -> Void

    private var trimmed: String { urlString.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var parsedURL: URL? { URL(string: trimmed).flatMap { $0.scheme != nil ? $0 : nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Open Pad by URL").font(.title3.bold())
            Text("Paste a CoderPad pad URL. It opens in the in-app browser window.")
                .foregroundStyle(.secondary)
                .font(.callout)
            TextField("https://app.coderpad.io/…", text: $urlString)
                .textFieldStyle(.roundedBorder)
                .onSubmit { if let url = parsedURL { onSubmit(url) } }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                Button("Open") {
                    if let url = parsedURL { onSubmit(url) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(parsedURL == nil)
            }
        }
        .padding()
        .frame(minWidth: 480)
    }
}

// MARK: - Split into small structs to reduce body type complexity

private struct MainSplit: View {
    @State private var store = AccountsStore.shared
    @Binding var section: AppSection
    @Binding var showSettings: Bool
    let directory: OrgDirectory
    let monitor: AccountHealthMonitor

    @State private var padSelection: Pad?
    @State private var questionSelection: Question?

    /// Drives the sidebar collapse/expand. With the title bar hidden there's no
    /// system toolbar to host the automatic sidebar toggle, so we own this state
    /// and surface our own toggle in the titlebar instead.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    /// Floor for the content column: the natural width of the active section's
    /// filter bar, so it can never be dragged too thin to hold all filters.
    @State private var contentMinWidth: CGFloat = 380

    private var isSidebarCollapsed: Bool { columnVisibility != .all }

    private func toggleSidebar() {
        withAnimation(.snappy) {
            if isSidebarCollapsed {
                columnVisibility = .all
            } else {
                columnVisibility = sectionHasDetail ? .doubleColumn : .detailOnly
            }
        }
    }

    /// Pads and Questions drive a detail pane; Organization and Quota are
    /// single-pane sections, so they drop the third column entirely.
    private var sectionHasDetail: Bool {
        switch section {
        case .pads, .questions: return true
        case .organization, .quota: return false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let id = store.currentAccountID, monitor.isUnauthorized(id) {
                UnauthorizedBanner(showSettings: $showSettings, monitor: monitor)
            }
            Group {
                if sectionHasDetail {
                    threeColumnSplit
                } else {
                    twoColumnSplit
                }
            }
        }
        // Pin the sidebar toggle in the titlebar (right of the traffic lights),
        // which the hidden title bar leaves transparent over the sidebar.
        .background(
            TitlebarLeadingAccessory {
                SidebarToggleButton(action: toggleSidebar)
            }
        )
        .task(id: store.currentAccountID) {
            if let account = store.currentAccount {
                if let raw = UserDefaults.standard.string(forKey: "section.\(account.id.uuidString)"),
                   let s = AppSection(rawValue: raw) {
                    section = s
                }
                // Warm the list(s) not currently on screen right away — concurrently with
                // the directory and health checks rather than queued behind them — so the
                // first switch to Pads/Questions has data ready instead of a spinner.
                async let warmed: Void = prefetchInactiveSections(account: account, active: section)
                await directory.load(for: account)
                await monitor.checkCurrentAccount()
                monitor.start()
                await warmed
            }
        }
        .onChange(of: section) { _, newValue in
            if let account = store.currentAccount {
                UserDefaults.standard.set(newValue.rawValue,
                                          forKey: "section.\(account.id.uuidString)")
            }
        }
        .onChange(of: store.currentAccountID) { _, _ in
            padSelection = nil
            questionSelection = nil
        }
    }

    /// Fetches whichever lists aren't currently displayed and stores them in the
    /// shared caches (which also persist to disk). The visible section loads itself,
    /// so we skip it here to avoid a duplicate request.
    private func prefetchInactiveSections(account: Account, active: AppSection) async {
        guard account.isMock || !account.apiKey.isEmpty else { return }
        let client = account.isMock ? CoderPadClient.mock() : CoderPadClient.live(apiKey: account.apiKey, baseURL: account.resolvedBaseURL)
        let id = account.id
        // Stream pages so the cache is warm from page 1 — the first switch shows the
        // top (most-recently-updated) pads immediately while the rest fill in behind it,
        // instead of waiting for every page of a large org to land.
        if active != .pads {
            var latest: [Pad] = []
            do {
                for try await snapshot in client.listPadsIncrementally() {
                    latest = snapshot
                    // Warm memory per page (cheap); persist the final list once below.
                    PadsCacheStore.shared.set(id, pads: snapshot, persist: false)
                }
                PadsCacheStore.shared.set(id, pads: latest)
            } catch {
                // Partial results still warm the UI; persist whatever arrived.
                if !latest.isEmpty { PadsCacheStore.shared.set(id, pads: latest) }
            }
        }
        if active != .questions, let questions = try? await client.listQuestions(sort: "updated_at,desc") {
            QuestionsCacheStore.shared.set(id, questions: questions)
        }
    }

    private var threeColumnSplit: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            Sidebar(section: $section, showSettings: $showSettings)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
                .navigationTitle("")
                .toolbar(removing: .sidebarToggle)
        } content: {
            SectionContent(
                section: section,
                padSelection: $padSelection,
                questionSelection: $questionSelection
            )
            .onPreferenceChange(FilterBarWidthKey.self) { contentMinWidth = $0 }
            .navigationSplitViewColumnWidth(
                min: contentMinWidth,
                ideal: max(480, contentMinWidth),
                max: max(760, contentMinWidth)
            )
        } detail: {
            SectionDetail(
                section: section,
                padSelection: $padSelection,
                questionSelection: $questionSelection
            )
            .navigationSplitViewColumnWidth(min: 360, ideal: 520)
        }
    }

    private var twoColumnSplit: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            Sidebar(section: $section, showSettings: $showSettings)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
                .navigationTitle("")
                .toolbar(removing: .sidebarToggle)
        } detail: {
            SectionContent(
                section: section,
                padSelection: $padSelection,
                questionSelection: $questionSelection
            )
        }
    }
}

/// The fixed sidebar toggle, centered on the traffic-light row via the titlebar
/// accessory. Same position whether the sidebar is shown or hidden.
private struct SidebarToggleButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "sidebar.left")
                .font(.system(size: 14, weight: .medium))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("Toggle Sidebar")
        .accessibilityLabel("Toggle Sidebar")
    }
}

/// Hosts a SwiftUI control in the window's titlebar, pinned to the leading edge
/// just right of the traffic lights and vertically centered on that row. Living
/// in the titlebar rather than a split column keeps it fixed when the sidebar
/// collapses or expands — and AppKit handles the alignment for us.
private struct TitlebarLeadingAccessory<Content: View>: NSViewRepresentable {
    @ViewBuilder var content: Content

    func makeNSView(context: Context) -> NSView { AccessoryAnchor(content: content) }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? AccessoryAnchor<Content>)?.update(content: content)
    }

    final class AccessoryAnchor<C: View>: NSView {
        private var accessory: NSTitlebarAccessoryViewController?
        private var hosting: NSHostingView<C>?
        private let initialContent: C

        init(content: C) {
            self.initialContent = content
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, accessory == nil else { return }
            let hosting = NSHostingView(rootView: initialContent)
            hosting.frame = NSRect(x: 0, y: 0, width: 40, height: 28)
            let controller = NSTitlebarAccessoryViewController()
            controller.view = hosting
            controller.layoutAttribute = .leading
            window.addTitlebarAccessoryViewController(controller)
            self.accessory = controller
            self.hosting = hosting
        }

        func update(content: C) {
            hosting?.rootView = content
        }
    }
}

private struct UnauthorizedBanner: View {
    @Binding var showSettings: Bool
    let monitor: AccountHealthMonitor

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.shield.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("This API key was rejected by CoderPad")
                    .font(.callout.weight(.semibold))
                Text("Open Settings and update or replace the key for this account.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Settings") { showSettings = true }
                .controlSize(.small)
            Button("Recheck") {
                Task { await monitor.checkCurrentAccount() }
            }
            .controlSize(.small)
        }
        .padding(.horizontal, Spacing.bannerH)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.18))
    }
}

/// The vibrant translucent material macOS source lists use. Painted as the
/// sidebar's background (extended under the titlebar) so the traffic lights read
/// as sitting on the sidebar, the way they do in Mail.
private struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private struct Sidebar: View {
    @Binding var section: AppSection
    @Binding var showSettings: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                sidebarRow(.pads, "Pads", "doc.text")
                sidebarRow(.questions, "Questions", "questionmark.bubble")
                sidebarRow(.organization, "Organization", "building.2")
                sidebarRow(.quota, "Quota", "gauge.with.dots.needle.67percent")
            }
            .padding(.horizontal, 8)
            .padding(.top, 10)
            Spacer(minLength: 0)
            Divider()
            AccountFooter(showSettings: $showSettings)
                .padding(10)
                .background(.thinMaterial)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Paint the vibrant sidebar material all the way up behind the titlebar,
        // so the traffic lights sit on the sidebar like Mail. The rows above still
        // respect the safe area, so only the material extends under the lights.
        .background(SidebarMaterial().ignoresSafeArea())
    }

    @ViewBuilder
    private func sidebarRow(_ value: AppSection, _ label: String, _ icon: String) -> some View {
        let isSelected = section == value
        Button {
            section = value
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 18)
                Text(label)
                Spacer(minLength: 0)
            }
            .font(.callout)
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .background(
                isSelected
                ? Color.primary.opacity(0.12)
                : Color.clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct InlineSearchField: View {
    @Binding var query: String
    var prompt: String = "Search"
    /// Optional external focus binding so a pane can drive focus (e.g. from ⌘F).
    var focused: FocusState<Bool>.Binding? = nil

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.callout)
            TextField(prompt, text: $query)
                .textFieldStyle(.plain)
                .font(.callout)
                .modifier(OptionalFocus(binding: focused))
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.subtleStroke.opacity(0.6), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// Applies a `.focused` binding only when one is supplied, so `InlineSearchField`
/// can stay usable both with and without an external focus driver.
private struct OptionalFocus: ViewModifier {
    let binding: FocusState<Bool>.Binding?

    func body(content: Content) -> some View {
        if let binding {
            content.focused(binding)
        } else {
            content
        }
    }
}

private struct AccountFooter: View {
    @State private var store = AccountsStore.shared
    @Binding var showSettings: Bool
    @State private var addingAccount: Account?

    var body: some View {
        HStack(spacing: 10) {
            if let current = store.currentAccount {
                AvatarCircle(label: current.name, diameter: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(current.name).font(.callout.weight(.medium)).lineLimit(1)
                    Text(store.accounts.count > 1 ? "Active · \(store.accounts.count) accounts" : "Active account")
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(-1)
            }
            Spacer()
            addAccountButton
            footerMenu
        }
        .sheet(item: $addingAccount) { account in
            AccountEditor(initial: account) { saved in
                store.add(saved)
                addingAccount = nil
            } onCancel: {
                addingAccount = nil
            }
        }
    }

    private var addAccountButton: some View {
        Button { addingAccount = newAccountDraft() } label: {
            Image(systemName: "person.crop.circle.badge.plus")
        }
        .buttonStyle(.borderless)
        .help("Add account")
        .accessibilityLabel("Add account")
    }

    /// A blank draft to add, or — when option is held and the dev env vars are
    /// set — one pre-filled from `CODERPAD_API_KEY` for quick real-data testing.
    private func newAccountDraft() -> Account {
        if NSEvent.modifierFlags.contains(.option), let dev = Account.fromDevEnvironment() {
            return dev
        }
        return Account(name: "", apiKey: "")
    }

    @ViewBuilder
    private var footerMenu: some View {
        Menu {
            if store.accounts.count > 1, let currentID = store.currentAccountID {
                Picker("Switch Account", selection: Binding(
                    get: { currentID },
                    set: { store.currentAccountID = $0 }
                )) {
                    ForEach(store.accounts) { account in
                        Text(account.name).tag(account.id)
                    }
                }
                Divider()
            }
            Button("Add Account…") { addingAccount = Account(name: "", apiKey: "") }
            Divider()
            Button("Settings…") { showSettings = true }
                .keyboardShortcut(",", modifiers: [.command])
        } label: {
            Image(systemName: "chevron.up.chevron.down")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Account menu")
    }
}

private struct SectionContent: View {
    @State private var store = AccountsStore.shared
    let section: AppSection
    @Binding var padSelection: Pad?
    @Binding var questionSelection: Question?

    var body: some View {
        if let account = store.currentAccount {
            let client = account.isMock ? CoderPadClient.mock() : CoderPadClient.live(apiKey: account.apiKey, baseURL: account.resolvedBaseURL)
            switch section {
            case .pads: PadsView(client: client, selection: $padSelection).id(account.id)
            case .questions: QuestionsView(client: client, selection: $questionSelection).id(account.id)
            case .organization: OrganizationView(client: client).id(account.id)
            case .quota: QuotaView(client: client).id(account.id)
            }
        }
    }
}

private struct SectionDetail: View {
    @State private var store = AccountsStore.shared
    let section: AppSection
    @Binding var padSelection: Pad?
    @Binding var questionSelection: Question?

    var body: some View {
        if let account = store.currentAccount {
            let client = account.isMock ? CoderPadClient.mock() : CoderPadClient.live(apiKey: account.apiKey, baseURL: account.resolvedBaseURL)
            switch section {
            case .pads:
                if let pad = padSelection {
                    PadDetailView(client: client, pad: pad).id(pad.id)
                } else {
                    ContentUnavailableView("Select a pad", systemImage: "doc.text",
                                           description: Text("Pick a pad to see its details."))
                }
            case .questions:
                if let question = questionSelection {
                    QuestionDetailView(client: client, question: question).id(question.id)
                } else {
                    ContentUnavailableView("Select a question", systemImage: "questionmark.bubble",
                                           description: Text("Pick a question to see its details."))
                }
            case .organization, .quota:
                ContentUnavailableView("Nothing selected", systemImage: "sidebar.squares.leading",
                                       description: Text("This section shows everything in the list."))
            }
        }
    }
}

#Preview { ContentView() }
