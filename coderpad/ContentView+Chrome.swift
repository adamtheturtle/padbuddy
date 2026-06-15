//
//  ContentView+Chrome.swift
//  coderpad
//

import SwiftUI

struct UnauthorizedBanner: View {
    let monitor: AccountHealthMonitor
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.shield.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("This API key was rejected by CoderPad")
                    .font(.callout.weight(.semibold))
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
            Image(systemName: "wifi.slash")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("You’re offline")
                    .font(.callout.weight(.semibold))
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
