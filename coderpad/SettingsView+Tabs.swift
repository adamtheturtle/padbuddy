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
                            // The rollback assignment below re-runs this handler with
                            // the real service state; skip that no-op pass so it can't
                            // clear the error the failed attempt just surfaced (#773).
                            guard enabled != LoginItem.isEnabled else { return }

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

            padHistorySection

            Section {
                Toggle("Make pads and questions searchable in Spotlight", isOn: $spotlightIndexing)
                    .onChange(of: spotlightIndexing) { _, isOn in
                        updateSpotlightIndexing(isOn)
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
                        // If permission is denied (or the request fails), revert the
                        // toggle instead of leaving an enabled-looking setting whose
                        // alerts are all silently dropped (#836).
                        guard isOn else { return }

                        Task { @MainActor in
                            let isAvailable = await PadUpdateNotifier.shared.alertAuthorizationIsAvailable()
                            if !isAvailable, notifyOnPadUpdates {
                                notifyOnPadUpdates = false
                            }
                        }
                    }
                if notifyOnPadUpdates {
                    Toggle("Hide pad titles in alerts", isOn: $hidePadTitlesInNotifications)
                }
            } footer: {
                Text(notifyOnPadUpdates
                    ? "Alerts when pads gain activity while PadBuddy is in the background. "
                    + "Pad titles can include candidate names, and alerts appear on the lock screen."
                    : "Alerts when pads gain activity while PadBuddy is in the background.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        // Re-sync with the system in case the login item changed outside the app.
        .onAppear { launchAtLogin = LoginItem.isEnabled }
    }

    private func updateSpotlightIndexing(_ isOn: Bool) {
        guard isOn else {
            SpotlightIndexer.clearAll()
            return
        }

        SpotlightIndexer.seedFromCaches()
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
            // Removal asks first (#772): deleting an account discards its stored API
            // key irreversibly, so the minus button gets the same confirmation as the
            // editor's own delete button.
            AddRemoveControl(
                onAdd: { addingAccount = Account(name: "", apiKey: "") },
                onRemove: { accountPendingRemoval = selectedAccountID },
                canRemove: selectedAccountID != nil
            )

            Spacer()

            // The demo accounts now live behind magic API keys rather than a button:
            // typing `demo` (mock data) or `baddemo` (revoked key) into a new account's
            // key field summons them (#549). This keeps demo creation Release-safe for
            // first-run users and App Review (see the App Review notes) without a
            // bespoke control in the toolbar.
        }
        .alert(
            "Delete this account?",
            isPresented: .init(
                get: { accountPendingRemoval != nil },
                set: { if !$0 { accountPendingRemoval = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Account", role: .destructive) {
                if let id = accountPendingRemoval {
                    store.remove(id: id)
                    if selectedAccountID == id { selectedAccountID = nil }
                }
                accountPendingRemoval = nil
            }
        } message: {
            Text("""
            \u{201C}\(pendingRemovalName)\u{201D} and its stored API key will be removed \
            from this Mac. This can\u{2019}t be undone.
            """)
        }
    }

    /// The display name for the account the sidebar minus button is about to remove.
    private var pendingRemovalName: String {
        accountPendingRemoval
            .flatMap { id in store.accounts.first { $0.id == id } }?.name ?? ""
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
}
