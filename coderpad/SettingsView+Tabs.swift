//
//  SettingsView+Tabs.swift
//  coderpad
//

import SwiftUI

extension SettingsView {
    var generalTab: some View {
        Form {
            // Launch-at-login is macOS-only (SMAppService); no iPad equivalent.
            #if os(macOS)
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
            #endif

            Section {
                appearanceSetting
            }

            // Dock / menu-bar presence is macOS-only. The active-pad badge is shared,
            // but each platform names the surface users actually see.
            #if os(macOS)
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
            #endif

            badgeSettingsSection

            Section {
                Toggle("Make pads and questions searchable in Spotlight", isOn: $spotlightIndexing)
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
                Text("Indexed on this device only. Pad and question titles can include candidate names.")
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
        }
        .formStyle(.grouped)
        // Re-sync with the system in case the login item changed outside the app.
        .onAppear { launchAtLogin = LoginItem.isEnabled }
    }

    @ViewBuilder
    var appearanceSetting: some View {
        #if os(macOS)
            LabeledContent("Appearance") {
                AppearancePicker(selection: appearanceSchemeBinding)
            }
        #else
            if horizontalSizeClass == .compact {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            } else {
                LabeledContent("Appearance") {
                    AppearancePicker(selection: appearanceSchemeBinding)
                }
            }
        #endif
    }

    /// Mail-style master-detail layout: a sidebar listing the accounts with `+`/`−`
    /// controls at its foot, and a detail pane showing the selected account's settings
    /// inline rather than in a modal sheet.
    /// The master-detail container: `HSplitView` on macOS; a plain `HStack` on iPad, which
    /// has no `HSplitView` (the settings sheet is a fixed width, so no draggable divider).
    @ViewBuilder private var accountsSplit: some View {
        #if os(macOS)
            HSplitView {
                accountsSidebar
                    .frame(minWidth: 200, idealWidth: 220, maxWidth: 320)
                accountDetail
                    .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
            }
        #else
            if horizontalSizeClass == .compact {
                compactAccountsView
            } else {
                HStack(spacing: 0) {
                    accountsSidebar
                        .frame(minWidth: 200, idealWidth: 220, maxWidth: 320)
                    accountDetail
                        .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        #endif
    }

    var accountsTab: some View {
        accountsSplit
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

    #if !os(macOS)
        @ViewBuilder
        var compactAccountsView: some View {
            if store.accounts.isEmpty {
                accountDetailPlaceholder
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal)
            } else {
                List {
                    Section {
                        ForEach(store.accounts) { account in
                            NavigationLink {
                                compactAccountEditor(for: account.id)
                            } label: {
                                AccountRow(
                                    account: account,
                                    isCurrent: account.id == store.currentAccountID && !store.isMergedView
                                )
                            }
                        }
                    }

                    Section {
                        Button {
                            addingAccount = Account(name: "", apiKey: "")
                        } label: {
                            Label("Add Account", systemImage: "plus")
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .navigationTitle("Accounts")
            }
        }

        func compactAccountEditor(for id: UUID) -> some View {
            ScrollView {
                if let account = store.accounts.first(where: { $0.id == id }) {
                    AccountEditor(
                        initial: account,
                        embedded: true,
                        isCurrent: id == store.currentAccountID && !store.isMergedView,
                        onUse: {
                            store.showAllAccounts = false
                            store.currentAccountID = id
                        },
                        onSave: { updated in store.update(updated) },
                        onCancel: {},
                        onDelete: { store.remove(id: id) },
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
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
        }
    #endif

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

            // The demo accounts now live behind magic API keys rather than a button:
            // typing `demo` (mock data) or `baddemo` (revoked key) into a new account's
            // key field summons them (#549). This keeps demo creation Release-safe for
            // first-run users and App Review (see the App Review notes) without a
            // bespoke control in the toolbar.
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
                    onUse: {
                        store.showAllAccounts = false
                        store.currentAccountID = id
                    },
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
            // Choosing a specific external browser app and opening it in the background
            // are macOS-only; on iPad external links always go to the system default.
            #if os(macOS)
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
            #endif
        }
        .formStyle(.grouped)
    }

    var menuBarTab: some View {
        Form {
            // The tab is always present (#608) so the Settings layout stays stable; when
            // the menu-bar icon is turned off (Dock-only mode) the controls below have no
            // effect, so explain that and disable them rather than making the whole tab
            // vanish and reappear.
            if !presence.showsMenuBarIcon {
                Section {
                    Text("The menu-bar icon is turned off. Turn it on under General, "
                        + "“Show PadBuddy in”, to use these settings.")
                        .foregroundStyle(.secondary)
                }
            }

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
        .disabled(!presence.showsMenuBarIcon)
    }
}
