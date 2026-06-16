//
//  ContentView+AccountFooter.swift
//  coderpad
//

import AppKit
import SwiftUI

struct AccountFooter: View {
    @State private var store = AccountsStore.shared
    @State private var monitor = AccountHealthMonitor.shared
    @State private var addingAccount: Account?
    /// Size of the combined-view glyph, paired with (and roughly matching) the 30pt
    /// avatar shown in the single-account branch. Scales with the user's text size so
    /// it honors accessibility sizing; the two branches are mutually exclusive, so this
    /// growing independently of the fixed avatar never causes a mismatch.
    @ScaledMetric(relativeTo: .largeTitle) private var mergedIconSize: CGFloat = 28

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
        if store.currentAccount != nil {
            Menu {
                // Direct Buttons (not a Picker): a Picker inside a Menu desyncs
                // AppKit's cached menu-item reps during tracking ("rep returned
                // item view with wrong item"). Matches the menu-bar switcher.
                if store.mergeableAccounts.count >= 2 {
                    Button {
                        store.showAllAccounts = true
                    } label: {
                        if store.isMergedView {
                            Label("All Accounts", systemImage: "checkmark")
                        } else {
                            Text("All Accounts")
                        }
                    }
                    Divider()
                }
                ForEach(store.accounts) { account in
                    Button {
                        store.showAllAccounts = false
                        store.currentAccountID = account.id
                    } label: {
                        accountMenuLabel(for: account)
                    }
                }
                Divider()
                Button("Add Account…") { addingAccount = Account(name: "", apiKey: "") }
                SettingsLink {
                    Text("Settings…")
                }
            } label: {
                triggerLabel
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

    /// A single account's menu row. An account the health monitor has flagged as
    /// unauthorized gets a warning triangle and a "(bad key)" suffix; otherwise the
    /// checkmark (when active) or the account's own icon takes the symbol slot.
    @ViewBuilder
    private func accountMenuLabel(for account: Account) -> some View {
        let isSelected = !store.isMergedView && account.id == store.currentAccount?.id
        let isUnauthorized = monitor.isUnauthorized(account.id)
        let title = isUnauthorized ? String(localized: "\(account.name) (bad key)") : account.name
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

    /// The menu's trigger: the active account's identity, or "All Accounts" while
    /// the combined view is on.
    private var triggerLabel: some View {
        let isMerged = store.isMergedView
        let title = isMerged ? String(localized: "All Accounts") : (store.currentAccount?.name ?? "")
        let subtitle = isMerged
            ? String(localized: "\(store.mergeableAccounts.count) accounts combined")
            : (store.accounts.count > 1
                ? String(localized: "Active · \(store.accounts.count) accounts")
                : String(localized: "Active account"))
        // The unauthorized state is shown only as a red warning triangle over the
        // avatar — color- and icon-only — so name it for VoiceOver, the way the menu
        // rows already append "(bad key)" (#79).
        let unauthorized = !isMerged && (store.currentAccount.map { monitor.isUnauthorized($0.id) } ?? false)
        let accessibilityLabel = [title, subtitle, unauthorized ? String(localized: "API key invalid") : ""]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        return HStack(spacing: 10) {
            if isMerged {
                Image(systemName: "person.2.circle.fill")
                    .font(.system(size: mergedIconSize))
                    .foregroundStyle(.purple)
            } else if let account = store.currentAccount {
                AvatarCircle(account: account, diameter: 30)
                    .overlay(alignment: .bottomTrailing) {
                        if monitor.isUnauthorized(account.id) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.red)
                                .background(Circle().fill(.background).padding(-1))
                                .help("This account's API key is invalid")
                        }
                    }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium)).lineLimit(1)
                Text(subtitle)
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
        // Read the avatar/title/subtitle/chevron as one phrase so VoiceOver lands on a
        // single, meaningful element instead of stepping through decorative glyphs.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }
}
