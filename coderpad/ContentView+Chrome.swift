//
//  ContentView+Chrome.swift
//  coderpad
//

import SwiftUI

struct UnauthorizedBanner: View {
    let monitor: AccountHealthMonitor
    @Environment(\.openAppSettings) private var openSettings

    var body: some View {
        HStack(spacing: 10) {
            // Decorative: the banner text already states the key was rejected, so the
            // symbol is hidden from VoiceOver rather than announced as "exclamationmark
            // shield fill, image" before the message.
            Image(systemName: "exclamationmark.shield.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("This API key was rejected by CoderPad")
                    .font(.callout.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("Open Settings and update or replace the key for this account.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Settings") {
                let navigation = SettingsNavigation.shared
                navigation.selectedTab = .accounts
                navigation.accountToEdit = AccountsStore.shared.currentAccountID
                openSettings()
            }
            .controlSize(.small)
            Button("Recheck") {
                Task { await monitor.checkCurrentAccount() }
            }
            .controlSize(.small)
        }
        .padding(.horizontal, Spacing.bannerH)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.18))
    }
}

/// Shown across the top of the window while the app is offline, mirroring the
/// `UnauthorizedBanner`'s look so a read-only state reads the same whether the key
/// was rejected or the network dropped (#321). No buttons: connectivity returns on
/// its own, and the banner clears itself the moment `NetworkMonitor` sees a path.
struct OfflineBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            // Decorative: the "You're offline" text carries the meaning, so the symbol
            // is hidden from VoiceOver rather than read out as a separate element.
            Image(systemName: "wifi.slash")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("You’re offline")
                    .font(.callout.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("CoderPad is unreachable, so editing is paused until you reconnect.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.bannerH)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.18))
    }
}
