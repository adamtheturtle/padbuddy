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
                } else {
                    Text("Open CoderPad automatically when you log in to your Mac.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                LabeledContent("Appearance") {
                    AppearancePicker(selection: $appearance)
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
                Picker("Dock badge", selection: $dockBadgeMode) {
                    ForEach(DockBadge.Mode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .onChange(of: dockBadgeMode) { _, _ in
                    // Apply or clear the badge immediately rather than waiting for the
                    // next pad refresh.
                    DockBadge.refresh()
                }
                .disabled(hideDockIcon)
            } footer: {
                Text("""
                Badge the Dock icon with a count across all your accounts: the started pads \
                (a live interview in progress), or the pads with new activity since you last \
                marked them seen. Choose Off for a clean icon.
                """)
                .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Require Touch ID to reveal API keys", isOn: biometricGateBinding)
            } footer: {
                Text("""
                When on, showing a saved API key in Settings must be unlocked with Touch ID \
                (or your login password on Macs without it). Turning this off requires the \
                same check, so it can't be bypassed from an unlocked Mac.
                """)
                .foregroundStyle(.secondary)
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
                Text("""
                Mirror your pads and questions into the on-device Spotlight index so you can find \
                them from system search. The index stays on this Mac; nothing is uploaded. Off by \
                default because pad titles can include candidate names.
                """)
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
            } footer: {
                Text("""
                How often pads and questions reload in the background. Large organizations refresh \
                less often automatically.
                """)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        // Re-sync with the system in case the login item changed outside the app.
        .onAppear { launchAtLogin = LoginItem.isEnabled }
    }

    /// Human-readable form of the auto-refresh interval, e.g. "90s" or "2m 30s".
    var refreshIntervalLabel: String {
        let seconds = refreshSeconds
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        let remainder = seconds % 60
        return remainder == 0 ? "\(minutes)m" : "\(minutes)m \(remainder)s"
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
                        .disabled(store.accounts.contains(where: \.isBadKeyDemo))
                } label: {
                    Image(systemName: "wand.and.stars")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("""
                Add a sandbox account backed by mock data, or one that simulates a revoked key \
                (DEBUG builds only).
                """)
            #endif
        }
        .buttonStyle(.borderless)
    }

    @ViewBuilder
    var accountDetail: some View {
        if let id = selectedAccountID,
           let account = store.accounts.first(where: { $0.id == id }) {
            // Editing a saved account. `onUse` makes it the active account (Mail's
            // "Enable this account"); `.id(id)` reloads the draft when the selection
            // changes so edits don't bleed between accounts.
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
                Text("""
                Please note that some third-party browsers do not support opening links \
                in the background.
                """)
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
            } footer: {
                Text("Controls how many recent pads and questions appear in the menu bar item.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show only started pads", isOn: $menuBarStartedOnly)
            } footer: {
                Text("""
                When on, the menu bar lists only your active (started) pads, hiding ended \
                and pending ones.
                """)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct AccountRow: View {
    let account: Account
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 10) {
            AvatarCircle(account: account, diameter: 30)

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
