//
//  ContentView+AccountFooter.swift
//  coderpad
//

import AppKit
import SwiftUI

struct AccountFooter: View {
    @State private var store = AccountsStore.shared
    @State private var addingAccount: Account?

    var body: some View {
        HStack(spacing: 10) {
            accountMenu
            Spacer()
            addAccountButton
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

    /// The whole account identity (avatar + name) is the menu trigger, and the
    /// accounts are listed directly as top-level items — so switching is open →
    /// pick, instead of burying the choice under a nested "Switch Account" submenu.
    @ViewBuilder
    private var accountMenu: some View {
        if let current = store.currentAccount {
            Menu {
                // Direct Buttons (not a Picker): a Picker inside a Menu desyncs
                // AppKit's cached menu-item reps during tracking ("rep returned
                // item view with wrong item"). Matches the menu-bar switcher.
                ForEach(store.accounts) { account in
                    Button {
                        store.currentAccountID = account.id
                    } label: {
                        if account.id == current.id {
                            Label(account.name, systemImage: "checkmark")
                        } else {
                            Text(account.name)
                        }
                    }
                }
                Divider()
                Button("Add Account…") { addingAccount = Account(name: "", apiKey: "") }
                SettingsLink {
                    Text("Settings…")
                }
            } label: {
                HStack(spacing: 10) {
                    AvatarCircle(label: current.name, diameter: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(current.name).font(.callout.weight(.medium)).lineLimit(1)
                        Text(store.accounts.count > 1 ? "Active · \(store.accounts.count) accounts" : "Active account")
                            .font(.caption2).foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .fixedSize(horizontal: true, vertical: true)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .contentShape(.rect)
            }
            // `.button` (not `.borderlessButton`) lets the rich label lay out at
            // its natural size; the borderless style renders a narrow popup that
            // collapses the avatar and name down to just the initial.
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .accessibilityLabel("Switch account")
        }
    }
}
