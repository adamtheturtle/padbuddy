//
//  ContentView.swift
//  coderpad
//

import SwiftUI

enum AppSection: String, Hashable {
    case pads, questions, organization, quota
}

struct ContentView: View {
    @State private var store = AccountsStore.shared
    @State private var section: AppSection? = .pads
    @State private var showSettings = false
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
                    section: $section,
                    showSettings: $showSettings,
                    directory: directory,
                    monitor: monitor
                )
            }
        }

        .environment(\.openSettings, { showSettings = true })
        .environment(\.orgDirectory, directory)
        .onReceive(NotificationCenter.default.publisher(for: .sectionRequested)) { note in
            if let s = note.object as? AppSection { section = s }
        }
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
                Button("Add Account") { showSettings = true }
                    .buttonStyle(.borderedProminent)
                #if DEBUG
                Button("Try Demo") {
                    store.addDemoIfMissing()
                }
                #endif
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
    @Binding var section: AppSection?
    @Binding var showSettings: Bool
    let directory: OrgDirectory
    let monitor: AccountHealthMonitor

    var body: some View {
        VStack(spacing: 0) {
            if let id = store.currentAccountID, monitor.isUnauthorized(id) {
                UnauthorizedBanner(showSettings: $showSettings, monitor: monitor)
            }
            NavigationSplitView {
                Sidebar(section: $section, showSettings: $showSettings)
                    .navigationSplitViewColumnWidth(min: 200, ideal: 220)
            } detail: {
                DetailHost(section: section)
                    .task(id: store.currentAccountID) {
                        if let account = store.currentAccount {
                            if let raw = UserDefaults.standard.string(forKey: "section.\(account.id.uuidString)"),
                               let s = AppSection(rawValue: raw) {
                                section = s
                            }
                            await directory.load(for: account)
                            await monitor.checkCurrentAccount()
                        }
                    }
                    .onChange(of: section) { _, newValue in
                        if let account = store.currentAccount, let newValue {
                            UserDefaults.standard.set(newValue.rawValue,
                                                      forKey: "section.\(account.id.uuidString)")
                        }
                    }
            }
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
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.18))
    }
}

private struct Sidebar: View {
    @Binding var section: AppSection?
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
        .navigationTitle("CoderPad")
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

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.callout)
            TextField(prompt, text: $query)
                .textFieldStyle(.plain)
                .font(.callout)
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

private struct AccountFooter: View {
    @State private var store = AccountsStore.shared
    @Binding var showSettings: Bool

    var body: some View {
        HStack(spacing: 10) {
            if let current = store.currentAccount {
                AvatarCircle(label: current.name, diameter: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(current.name).font(.callout.weight(.medium)).lineLimit(1)
                    Text(store.accounts.count > 1 ? "Active · \(store.accounts.count) accounts" : "Active account")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            footerMenu
        }
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

private struct DetailHost: View {
    @State private var store = AccountsStore.shared
    let section: AppSection?

    var body: some View {
        if let account = store.currentAccount {
            let client = account.isMock ? CoderPadClient.mock() : CoderPadClient.live(apiKey: account.apiKey)
            switch section ?? .pads {
            case .pads: PadsView(client: client).id(account.id)
            case .questions: QuestionsView(client: client).id(account.id)
            case .organization: OrganizationView(client: client).id(account.id)
            case .quota: QuotaView(client: client).id(account.id)
            }
        }
    }
}

#Preview { ContentView() }
