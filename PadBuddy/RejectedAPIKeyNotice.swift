//
//  RejectedAPIKeyNotice.swift
//  PadBuddy
//

import SwiftUI

func rejectedAPIKeyMessage(for accounts: [Account]) -> String {
    if accounts.count == 1, let account = accounts.first {
        return String(localized: "The API key for \(account.name) was rejected.")
    }
    return String(localized: "API keys were rejected for \(accounts.count) accounts.")
}

/// One compact warning for the merged list, with account names available on hover
/// and to VoiceOver instead of wrapping a long list into the message.
struct RejectedAPIKeyNotice: View {
    let accounts: [Account]
    @Environment(\.openAppSettings) private var openSettings

    var body: some View {
        if let first = accounts.first {
            HStack(spacing: 6) {
                Image(systemName: "key.slash.fill")
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
                Text(rejectedAPIKeyMessage(for: accounts))
                    .foregroundStyle(.secondary)
                    .help(accounts.map(\.name).joined(separator: ", "))
                    .accessibilityValue(accounts.count > 1 ? accounts.map(\.name).joined(separator: ", ") : "")
                Button("Fix in Settings") {
                    let navigation = SettingsNavigation.shared
                    navigation.selectedTab = .accounts
                    navigation.accountToEdit = first.id
                    openSettings()
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                Spacer()
            }
        }
    }
}
