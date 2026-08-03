//
//  PhoneContentView+AccountMenu.swift
//  coderpad
//
//  The compact shell's trailing account/settings toolbar menu: the avatar label,
//  account switching (including All Accounts), and the Settings / Manage Accounts /
//  Add Account actions. Split from PhoneContentView.swift to keep it within the lint
//  file-length budget.
//

#if os(iOS)
    import SwiftUI

    extension PhoneContentView {
        var accountMenu: some View {
            Menu {
                accountMenuActions
            } label: {
                accountMenuLabel
            }
            .menuIndicator(.hidden)
            .accessibilityLabel("Account and settings")
        }

        @ViewBuilder
        var accountMenuActions: some View {
            if store.mergeableAccounts.count >= 2 {
                Button {
                    store.showAllAccounts = true
                } label: {
                    if store.isMergedView {
                        Label("All Accounts", systemImage: "checkmark")
                    } else {
                        Label("All Accounts", systemImage: "person.2")
                    }
                }
            }

            ForEach(store.accounts) { account in
                Button {
                    store.showAllAccounts = false
                    store.currentAccountID = account.id
                } label: {
                    accountMenuRow(for: account)
                }
                // An account with no key or a malformed endpoint can't load
                // anything; selecting it swapped the working account for a broken
                // scope (#1670). Manage Accounts remains the way to fix it.
                .disabled(!account.isMock && (account.apiKey.isEmpty || account.hasMalformedBaseURLOverride))
            }

            if !store.accounts.isEmpty {
                Divider()
            }
            Button { openGeneralSettings() } label: {
                Label("Settings", systemImage: "gearshape")
            }
            Button { manageAccounts() } label: {
                Label("Manage Accounts...", systemImage: "person.crop.circle")
            }
            Button { startAddingAccount() } label: {
                Label("Add Account...", systemImage: "plus")
            }
        }

        @ViewBuilder
        func accountMenuRow(for account: Account) -> some View {
            let isSelected = !store.isMergedView && account.id == store.currentAccount?.id
            let isUnauthorized = monitor.isUnauthorized(account.id)
            let name = accountDisplayName(for: account)
            let title = isUnauthorized ? String(localized: "\(name) (bad key)") : name
            if isSelected {
                Label(title, systemImage: "checkmark")
            } else if isUnauthorized {
                Label(title, systemImage: "exclamationmark.triangle.fill")
            } else if let symbol = account.iconSymbol {
                Label(title, systemImage: symbol)
            } else {
                Text(title)
            }
        }

        @ViewBuilder
        var accountMenuLabel: some View {
            if store.isMergedView {
                Image(systemName: "person.2.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            } else if let account = store.currentAccount {
                toolbarAccountAvatar(for: account)
                    .overlay(alignment: .bottomTrailing) {
                        if monitor.isUnauthorized(account.id) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.red)
                                .background(Circle().fill(.background).padding(-1))
                                .accessibilityHidden(true)
                        }
                    }
            } else {
                Image(systemName: "person.crop.circle")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }

        func toolbarAccountAvatar(for account: Account) -> some View {
            ZStack {
                Circle()
                    .fill(.primary.opacity(0.06))
                    .overlay(Circle().stroke(.primary.opacity(0.12), lineWidth: 1))
                if let symbol = account.iconSymbol {
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary.opacity(0.86))
                        .accessibilityHidden(true)
                } else {
                    Text(accountInitials(for: account))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary.opacity(0.86))
                }
            }
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)
        }

        func accountDisplayName(for account: Account) -> String {
            let name = account.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                return name
            }

            let email = account.userEmail.trimmingCharacters(in: .whitespacesAndNewlines)
            return email.isEmpty ? String(localized: "Unnamed Account") : email
        }

        func accountInitials(for account: Account) -> String {
            let words = accountDisplayName(for: account).split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            let initials = words.prefix(2).compactMap(\.first)
            return initials.isEmpty ? "?" : String(initials).uppercased()
        }

        func openGeneralSettings() {
            SettingsNavigation.shared.selectedTab = .general
            openSettings()
        }

        func startAddingAccount() {
            let navigation = SettingsNavigation.shared
            navigation.selectedTab = .accounts
            navigation.startAddingAccount = true
            openSettings()
        }

        func manageAccounts() {
            SettingsNavigation.shared.selectedTab = .accounts
            openSettings()
        }
    }
#endif
