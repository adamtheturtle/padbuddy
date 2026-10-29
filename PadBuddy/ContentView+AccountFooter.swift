//
//  ContentView+AccountFooter.swift
//  coderpad
//

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif
import SwiftUI

struct AccountFooter: View {
    @State private var store = AccountsStore.shared
    @State private var monitor = AccountHealthMonitor.shared
    @Environment(\.openAppSettings) private var openSettings
    var body: some View {
        let currentAccount = store.currentAccount
        HStack(spacing: 10) {
            accountMenu(currentAccount: currentAccount)
            Spacer()
            // With an account active, "Manage Accounts" lives in the switcher menu;
            // with none, surface it as the footer's sole entry point (#455).
            if currentAccount == nil {
                manageAccountsButton
            }
            #if !os(macOS)
                // iPad has no Settings scene / ⌘, so Settings would otherwise be
                // reachable only via the account menu's "Manage Accounts…" — which
                // reads as accounts, not preferences. Surface a visible gear (#600).
                settingsButton
            #endif
        }
    }

    #if !os(macOS)
        /// iOS-only Settings entry point: opens Settings on the General tab. macOS
        /// relies on ⌘, and the Settings menu instead, where this would be redundant.
        private var settingsButton: some View {
            Button {
                SettingsNavigation.shared.selectedTab = .general
                openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")
            .accessibilityLabel("Settings")
        }
    #endif

    /// Opens Settings on the Accounts tab — the single "manage accounts" entry point
    /// that replaces the footer's old separate Add Account button/sheet and Settings
    /// link (#455). Adding, editing, and removing accounts all happen on that tab.
    private func manageAccounts() {
        SettingsNavigation.shared.selectedTab = .accounts
        openSettings()
    }

    private var manageAccountsButton: some View {
        Button { manageAccounts() } label: {
            Label("Manage Accounts", systemImage: "person.crop.circle")
        }
        .buttonStyle(.borderless)
        .help("Add or manage accounts in Settings")
        .accessibilityLabel("Manage accounts")
    }

    /// The whole account identity (avatar + name) is the menu trigger, and the
    /// accounts are listed directly as top-level items — so switching is open →
    /// pick, instead of burying the choice under a nested "Switch Account" submenu.
    @ViewBuilder
    private func accountMenu(currentAccount: Account?) -> some View {
        if let currentAccount {
            Menu {
                // Native menu toggles expose checked state without introducing
                // the nested Picker reps that desynchronize during AppKit tracking.
                if store.mergeableAccounts.count >= 2 {
                    Toggle("All Accounts", isOn: Binding(
                        get: { store.isMergedView },
                        set: {
                            if $0 {
                                store.showAllAccounts = true
                            }
                        }
                    ))
                    Divider()
                }
                // De-duplicated by id: `ForEach` requires unique ids, and a duplicated
                // persisted record produced two rows for one account with an ambiguous
                // selection between them (#2228).
                ForEach(uniqueAccounts) { account in
                    Toggle(isOn: Binding(
                        get: { !store.isMergedView && store.currentAccountID == account.id },
                        set: { selected in
                            if selected {
                                store.showAllAccounts = false
                                store.currentAccountID = account.id
                            }
                        }
                    )) {
                        accountMenuLabel(for: account)
                    }
                    // An account with no key or a malformed endpoint can't load
                    // anything; selecting it swapped the working account for a broken
                    // scope. The compact shell's menu has disabled these since #1670 —
                    // this one still offered them, so the two menus presented different
                    // switch targets for the same account list (#2224). Manage Accounts
                    // remains the way to fix such an account.
                    .disabled(!account.isMock
                        && (account.apiKey.isEmpty || account.hasMalformedBaseURLOverride))
                }
                Divider()
                Button("Manage Accounts…") { manageAccounts() }
            } label: {
                // Deliberately NO hover platter here: a `Menu` hosts its label in its
                // own `UIHostingController`, so the label content is that host's root
                // view. A hover highlight has no valid sibling slot and can fall back to
                // adding `_UIPointerEffectPlatterView` straight onto `UIHostingController.view`,
                // which logs the unsupported view-hierarchy SwiftUI fault. Wrapping in a
                // SwiftUI container doesn't help because stacks are drawn into the host,
                // not backed by a distinct UIView.
                triggerLabel(currentAccount: currentAccount)
            }
            // `.button` (not `.borderlessButton`) lets the rich label lay out at
            // its natural size; the borderless style renders a narrow popup that
            // collapses the avatar and name down to just the initial.
            .menuStyle(.button)
            .buttonStyle(.plain)
            #if os(iOS)
                .hoverEffectDisabled(true)
            #endif
                .menuIndicator(.hidden)
                .accessibilityLabel("Switch account")
                .accessibilityValue(store.isMergedView
                    ? String(localized: "All Accounts") : Self.displayName(for: currentAccount))
        }
    }

    /// The accounts to list, one row per id. Duplicate persisted records would
    /// otherwise give `ForEach` repeated ids, which it does not support (#2228).
    private var uniqueAccounts: [Account] {
        var seen = Set<UUID>()
        return store.accounts.filter { seen.insert($0.id).inserted }
    }

    /// An account's label, never blank. `name` is user-entered and can be empty or
    /// whitespace-only, which left the trigger and its menu row unidentifiable — so
    /// fall back to the address, then to a generic name (#2233). Mirrors the compact
    /// shell's `accountDisplayName(for:)`.
    static func displayName(for account: Account) -> String {
        let name = account.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            return name
        }

        let email = account.userEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        return email.isEmpty ? String(localized: "Unnamed Account") : email
    }

    /// A single account's menu row. An account the health monitor has flagged as
    /// unauthorized gets a warning triangle and a "(bad key)" suffix; otherwise the
    /// account's own icon takes the symbol slot; the Toggle supplies checked state.
    @ViewBuilder
    private func accountMenuLabel(for account: Account) -> some View {
        let isUnauthorized = monitor.isUnauthorized(account.id)
        let name = Self.displayName(for: account)
        let title = isUnauthorized ? String(localized: "\(name) (bad key)") : name
        if isUnauthorized {
            Label(title, systemImage: "exclamationmark.triangle.fill")
        } else if let symbol = account.iconSymbol {
            Label(title, systemImage: symbol)
        } else {
            Text(title)
        }
    }

    /// The menu's trigger: the active account's identity, or "All Accounts" while
    /// the combined view is on.
    private func triggerLabel(currentAccount: Account) -> some View {
        let isMerged = store.isMergedView
        let title = isMerged ? String(localized: "All Accounts") : Self.displayName(for: currentAccount)
        let subtitle = isMerged
            ? String(localized: "\(store.mergeableAccounts.count) accounts combined")
            : (store.accounts.count > 1
                ? String(localized: "Active · \(store.accounts.count) accounts")
                : String(localized: "Active account"))
        // The unauthorized state is shown only as a red warning triangle over the
        // avatar — color- and icon-only — so name it for VoiceOver, the way the menu
        // rows already append "(bad key)" (#79).
        let unauthorized = !isMerged && monitor.isUnauthorized(currentAccount.id)
        let accessibilityLabel = [title, subtitle, unauthorized ? String(localized: "API key invalid") : ""]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        return HStack(spacing: 10) {
            if isMerged {
                AvatarCircle(label: title, diameter: 30, tint: .accentColor, symbol: "person.2.fill")
            } else {
                AvatarCircle(account: currentAccount, diameter: 30)
                    .overlay(alignment: .bottomTrailing) {
                        if monitor.isUnauthorized(currentAccount.id) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.red)
                                .accessibilityLabel("Authentication error")
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
        // The composed label names the invalid key, but not what to do about it. The
        // state is actionable — the menu is where the account is fixed — so say so
        // rather than leaving VoiceOver users with a bare error phrase (#2237).
        .accessibilityHint(unauthorized
            ? String(localized: "Opens the account switcher, where you can manage this account's API key.")
            : String(localized: "Opens the account switcher."))
    }
}
