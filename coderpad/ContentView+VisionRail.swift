//
//  ContentView+VisionRail.swift
//  coderpad
//

import SwiftUI

extension Sidebar {
    func visionNavigationRail(order: [AppSection]) -> some View {
        VStack(spacing: 14) {
            VStack(spacing: 10) {
                ForEach(order, id: \.self) { value in
                    visionRailSectionButton(value)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 14)
            .visionRailBackground()

            Spacer(minLength: 12)

            visionRailAccountMenu
                .padding(.bottom, 4)
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityLabel("Sections")
    }

    private func visionRailSectionButton(_ value: AppSection) -> some View {
        let isSelected = isRootSelected(value)

        return Button { selectRoot(value) } label: {
            Image(systemName: value.systemImage)
                .font(.system(size: 20, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.72))
                .frame(width: 48, height: 48)
                .background {
                    if isSelected {
                        Circle()
                            .fill(Color.accentColor.opacity(0.72))
                            .overlay(Circle().stroke(.white.opacity(0.26), lineWidth: 1))
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .visionRailHover()
        .help(value.label)
        .accessibilityLabel(Text(value.label))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var visionRailAccountMenu: some View {
        Menu {
            if accounts.mergeableAccounts.count >= 2 {
                Button {
                    accounts.showAllAccounts = true
                } label: {
                    if accounts.isMergedView {
                        Label("All Accounts", systemImage: "checkmark")
                    } else {
                        Text("All Accounts")
                    }
                }
                Divider()
            }

            ForEach(visionRailAccounts) { account in
                Button {
                    accounts.showAllAccounts = false
                    accounts.currentAccountID = account.id
                } label: {
                    let title = AccountFooter.displayName(for: account)
                    if !accounts.isMergedView, account.id == accounts.currentAccountID {
                        Label(title, systemImage: "checkmark")
                    } else if let symbol = account.iconSymbol {
                        Label(title, systemImage: symbol)
                    } else {
                        Text(title)
                    }
                }
                .disabled(!account.isMock && (account.apiKey.isEmpty || account.hasMalformedBaseURLOverride))
            }

            Divider()
            Button("Manage Accounts…") {
                SettingsNavigation.shared.selectedTab = .accounts
                openSettings()
            }
        } label: {
            visionRailAccountTrigger
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        #if os(iOS)
            .hoverEffectDisabled(true)
        #endif
            .menuIndicator(.hidden)
            .help("Switch account")
            .accessibilityLabel("Switch account")
    }

    private var visionRailAccountTrigger: some View {
        let currentAccount = accounts.currentAccount
        let title = currentAccount.map { AccountFooter.displayName(for: $0) } ?? String(localized: "Accounts")

        return Group {
            if accounts.isMergedView {
                AvatarCircle(label: String(localized: "All Accounts"),
                             diameter: 34,
                             tint: .accentColor,
                             symbol: "person.2.fill")
            } else if let currentAccount {
                AvatarCircle(account: currentAccount, diameter: 34)
            } else {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.72))
                    .frame(width: 34, height: 34)
            }
        }
        .frame(width: 52, height: 52)
        .background(.primary.opacity(0.08), in: Circle())
        .overlay(Circle().stroke(.primary.opacity(0.16), lineWidth: 1))
        .contentShape(Circle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }

    private var visionRailAccounts: [Account] {
        var seen = Set<UUID>()
        return accounts.accounts.filter { seen.insert($0.id).inserted }
    }
}
