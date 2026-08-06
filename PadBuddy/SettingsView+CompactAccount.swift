//
//  SettingsView+CompactAccount.swift
//  coderpad
//

#if !os(macOS)
    import SwiftUI

    extension SettingsView {
        func compactAccountEditor(for id: UUID) -> some View {
            ScrollView {
                if let account = store.accounts.first(where: { $0.id == id }) {
                    VStack(alignment: .leading, spacing: 16) {
                        AccountEditor(
                            initial: account,
                            embedded: true,
                            isCurrent: id == store.currentAccountID && !store.isMergedView,
                            onUse: {
                                store.showAllAccounts = false
                                store.currentAccountID = id
                            },
                            onSave: { updated in store.saveIfCredentialsUnique(updated) },
                            onCancel: {},
                            onDelete: { store.remove(id: id) },
                            onAppearanceChange: { symbol, tint in
                                guard var account = store.accounts.first(where: { $0.id == id }) else { return }

                                account.iconSymbol = symbol
                                account.tintHex = tint
                                store.update(account)
                            }
                        )
                    }
                    .id(id)
                } else {
                    accountDetailPlaceholder
                }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
#endif
