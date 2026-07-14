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
    /// Size of the combined-view glyph, paired with (and roughly matching) the 30pt
    /// avatar shown in the single-account branch. Scales with the user's text size so
    /// it honors accessibility sizing; the two branches are mutually exclusive, so this
    /// growing independently of the fixed avatar never causes a mismatch.
    @ScaledMetric(relativeTo: .largeTitle) private var mergedIconSize: CGFloat = 28

    var body: some View {
        HStack(spacing: 10) {
            accountMenu
            Spacer()
            // With an account active, "Manage Accounts" lives in the switcher menu;
            // with none, surface it as the footer's sole entry point (#455).
            if store.currentAccount == nil {
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
                Button("Manage Accounts…") { manageAccounts() }
            } label: {
                // Deliberately NO hover platter here: a `Menu` hosts its label in its
                // own `UIHostingController`, so the label content is that host's root
                // view. A hover highlight has no valid sibling slot and can fall back to
                // adding `_UIPointerEffectPlatterView` straight onto `UIHostingController.view`,
                // which logs the unsupported view-hierarchy SwiftUI fault. Wrapping in a
                // SwiftUI container doesn't help because stacks are drawn into the host,
                // not backed by a distinct UIView.
                triggerLabel
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
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: mergedIconSize))
                    .foregroundStyle(.secondary)
            } else if let account = store.currentAccount {
                AvatarCircle(account: account, diameter: 30)
                    .overlay(alignment: .bottomTrailing) {
                        if monitor.isUnauthorized(account.id) {
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
    }
}
