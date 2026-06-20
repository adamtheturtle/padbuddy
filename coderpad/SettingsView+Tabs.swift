//
//  SettingsView+Tabs.swift
//  coderpad
//

import SwiftUI

extension SettingsView {
    var generalTab: some View {
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
                }
            }

            Section {
                LabeledContent("Appearance") {
                    AppearancePicker(selection: $appearance)
                }
            }

            Section {
                Picker("Show PadBuddy in", selection: $presence) {
                    ForEach(AppPresence.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .onChange(of: presence) { _, _ in
                    // Switch the activation policy immediately; the menu-bar icon follows
                    // the same preference via the MenuBarExtra's isInserted binding.
                    GeneralSettings.applyDockVisibility()
                }
            }

            Section {
                Picker("Show my active pads on the Dock icon", selection: $dockBadgeScope) {
                    ForEach(DockBadgeScope.allCases) { scope in
                        Text(scope.label).tag(scope)
                    }
                }
                .onChange(of: dockBadgeScope) { _, scope in
                    // The Dock badge only renders once the app holds the `.badge`
                    // capability (macOS Monterey+, #317), so ask for it the moment the
                    // user switches the badge on — when the prompt is expected.
                    if scope != .off { PadUpdateNotifier.shared.requestBadgeAuthorization() }
                    // Apply or clear the badge immediately rather than waiting for the
                    // next pad refresh.
                    DockBadge.refresh()
                }
                .disabled(!presence.showsDockIcon)
            }

            Section {
                Toggle("Require Touch ID to reveal API keys", isOn: biometricGateBinding)
            }

            Section {
                Toggle("Make pads searchable in Spotlight", isOn: $spotlightIndexing)
                    .onChange(of: spotlightIndexing) { _, isOn in
                        if isOn {
                            // Index what's already cached so results appear without a refresh.
                            if let id = accountsStore.currentAccountID {
                                SpotlightIndexer.updatePads(PadsCacheStore.shared.get(id), account: id)
                                SpotlightIndexer.updateQuestions(QuestionsCacheStore.shared.get(id), account: id)
                            }
                        } else {
                            SpotlightIndexer.clearAll()
                        }
                    }
            } footer: {
                Text("Indexed on this Mac only. Pad titles can include candidate names.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Notify me when pads update", isOn: $notifyOnPadUpdates)
                    .onChange(of: notifyOnPadUpdates) { _, isOn in
                        // Ask for permission the moment they opt in, so the system
                        // prompt arrives when it's expected rather than at first alert.
                        if isOn { PadUpdateNotifier.shared.requestAuthorization() }
                    }
            } footer: {
                Text("Alerts when pads gain activity while PadBuddy is in the background.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Stepper(value: $refreshSeconds,
                        in: GeneralSettings.minRefreshSeconds ... GeneralSettings.maxRefreshSeconds,
                        step: 15) {
                    HStack {
                        Text("Auto-refresh interval")
                        Spacer()
                        Text(refreshIntervalLabel)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // About + the trademark / unofficial-client disclaimer (#40, #491). Phrased
            // as "This app" so it stays correct regardless of the app's display name.
            Section {
                LabeledContent("Version") {
                    Text(Self.appVersionString)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            } header: {
                Text("About")
            } footer: {
                // One multiline string literal (backslash-joined into a single line) so
                // it stays a localizable LocalizedStringKey rather than the verbatim
                // Text(String) overload, which wouldn't be extracted for translation.
                Text("""
                This app is an unofficial client for the CoderPad interview platform. \
                It is not affiliated with, authorized, maintained, or endorsed by CoderPad, Inc. \
                “CoderPad” is a trademark of CoderPad, Inc.
                """)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        // Re-sync with the system in case the login item changed outside the app.
        .onAppear { launchAtLogin = LoginItem.isEnabled }
    }

    /// The app's marketing version and build number for the About section, e.g.
    /// "1.0.9 (42)". Falls back gracefully if either key is somehow missing.
    static var appVersionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String
        if let build, build != short { return "\(short) (\(build))" }
        return short
    }

    /// Human-readable form of the auto-refresh interval, e.g. "90s" or "2m 30s".
    var refreshIntervalLabel: String {
        let seconds = refreshSeconds
        if seconds < 60 { return String(localized: "\(seconds)s") }
        let minutes = seconds / 60
        let remainder = seconds % 60
        return remainder == 0
            ? String(localized: "\(minutes)m")
            : String(localized: "\(minutes)m \(remainder)s")
    }

    /// Mail-style master-detail layout: a sidebar listing the accounts with `+`/`−`
    /// controls at its foot, and a detail pane showing the selected account's settings
    /// inline rather than in a modal sheet.
    var accountsTab: some View {
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

    var accountsSidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selectedAccountID) {
                ForEach(store.accounts) { account in
                    AccountRow(
                        account: account,
                        // In the merged "All Accounts" view no single account is
                        // current, so don't single one out (matches the menu bar).
                        isCurrent: account.id == store.currentAccountID && !store.isMergedView
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

    var sidebarToolbar: some View {
        HStack(spacing: 2) {
            // A single Mail-style segmented add/remove control: a rounded pill holding
            // +/- split by a hairline divider, rather than two free-standing buttons.
            AddRemoveControl(
                onAdd: { addingAccount = Account(name: "", apiKey: "") },
                onRemove: {
                    if let id = selectedAccountID {
                        store.remove(id: id)
                        selectedAccountID = nil
                    }
                },
                canRemove: selectedAccountID != nil
            )

            Spacer()

            // The "Mock data" demo ships in every build so first-run users — and App
            // Review, which runs a Release build with no API key — can explore the app
            // with sample data instead of landing on the empty "add a key" state
            // (#68, #76). The backing mock server is already Release-safe; only this
            // entry point was gated. "Bad API key" stays DEBUG-only: it's a testing
            // affordance for exercising the revoked-key UI, not something to surface to
            // real users.
            Menu {
                Button("Mock data") { store.addDemoIfMissing() }
                    .disabled(store.accounts.contains(where: { $0.isMock && !$0.isBadKeyDemo }))
                #if DEBUG
                    Button("Bad API key") { store.addDemoBadKeyIfMissing() }
                        .disabled(store.accounts.contains(where: \.isBadKeyDemo))
                #endif
            } label: {
                Image(systemName: "wand.and.stars")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Add a sandbox account backed by mock data to explore the app without an API key.")
        }
    }

    @ViewBuilder
    var accountDetail: some View {
        if let id = selectedAccountID,
           let account = store.accounts.first(where: { $0.id == id }) {
            // Editing a saved account. `onUse` makes it the active account (Mail's
            // "Enable this account"); `.id(id)` reloads the draft when the selection
            // changes so edits don't bleed between accounts.
            //
            // Wrapped in a ScrollView so an editor that's taller for one account (more
            // rows once validated, banners, etc.) scrolls within a fixed pane rather
            // than pushing the whole window taller — which would otherwise shift the
            // sidebar's +/− toolbar each time the selection changed.
            ScrollView {
                AccountEditor(
                    initial: account,
                    embedded: true,
                    isCurrent: id == store.currentAccountID && !store.isMergedView,
                    onUse: { store.currentAccountID = id },
                    onSave: { updated in store.update(updated) },
                    onCancel: {},
                    onDelete: {
                        store.remove(id: id)
                        selectedAccountID = nil
                    },
                    // Persist icon/tint immediately, merging only those fields onto the
                    // saved account so unsaved edits to other fields aren't flushed too.
                    onAppearanceChange: { symbol, tint in
                        guard var account = store.accounts.first(where: { $0.id == id }) else { return }

                        account.iconSymbol = symbol
                        account.tintHex = tint
                        store.update(account)
                    }
                )
                .id(id)
            }
        } else {
            accountDetailPlaceholder
        }
    }

    @ViewBuilder
    var accountDetailPlaceholder: some View {
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

    var browserTab: some View {
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
                Text("Some third-party browsers don't support this.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    var menuBarTab: some View {
        Form {
            Section {
                Stepper(value: $menuBarTopN, in: 0 ... 30, step: 1) {
                    HStack {
                        Text("Recent pads in menu bar")
                        Spacer()
                        Text("\(menuBarTopN)")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Toggle("Show only active pads", isOn: $menuBarStartedOnly)
            }
        }
        .formStyle(.grouped)
    }
}
