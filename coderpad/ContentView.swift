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

    var body: some View {
        Group {
            if store.currentAccount == nil {
                noAccountView
                    .frame(minWidth: 520, minHeight: 380)
            } else {
                NavigationSplitView {
                    sidebar
                        .navigationSplitViewColumnWidth(min: 200, ideal: 220)
                } detail: {
                    detailContent
                        .task(id: store.currentAccountID) {
                            if let account = store.currentAccount {
                                if let raw = UserDefaults.standard.string(forKey: "section.\(account.id.uuidString)"),
                                   let s = AppSection(rawValue: raw) {
                                    section = s
                                }
                                await directory.load(for: account)
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
        .environment(\.openSettings, { showSettings = true })
        .environment(\.orgDirectory, directory)
        .onReceive(NotificationCenter.default.publisher(for: .sectionRequested)) { note in
            if let s = note.object as? AppSection { section = s }
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
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $section) {
                SwiftUI.Section("Browse") {
                    Label("Pads", systemImage: "doc.text").tag(AppSection.pads)
                    Label("Questions", systemImage: "questionmark.bubble").tag(AppSection.questions)
                }
                SwiftUI.Section("Account") {
                    Label("Organization", systemImage: "building.2").tag(AppSection.organization)
                    Label("Quota", systemImage: "gauge.with.dots.needle.67percent").tag(AppSection.quota)
                }
            }
            .listStyle(.sidebar)

            Divider()
            accountFooter
                .padding(10)
                .background(.thinMaterial)
        }
        .navigationTitle("CoderPad")
    }

    private var accountFooter: some View {
        HStack(spacing: 10) {
            if let current = store.currentAccount {
                AvatarCircle(label: current.name, diameter: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(current.name).font(.callout.weight(.medium)).lineLimit(1)
                    Text(store.accounts.count > 1 ? "Active · \(store.accounts.count) accounts" : "Active account")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .font(.system(size: 22)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No account").font(.callout.weight(.medium))
                    Text("Add one in Settings").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Menu {
                if !store.accounts.isEmpty {
                    Picker("Switch", selection: Binding(
                        get: { store.currentAccountID ?? store.accounts.first?.id ?? UUID() },
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
        }
    }

    @ViewBuilder
    private var detailContent: some View {
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

    private var noAccountView: some View {
        ContentUnavailableView {
            Label("No account selected", systemImage: "person.crop.circle.badge.plus")
        } description: {
            Text("Open Settings to add an account with your CoderPad API key, or try the demo with mock data.")
        } actions: {
            Button("Open Settings") { showSettings = true }
                .buttonStyle(.borderedProminent)
            #if DEBUG
            Button("Try Demo (mock data)") {
                store.addDemoIfMissing()
            }
            #endif
            GetAPIKeyLink()
        }
    }
}

#Preview { ContentView() }
