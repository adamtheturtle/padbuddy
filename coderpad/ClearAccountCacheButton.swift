//
//  ClearAccountCacheButton.swift
//  coderpad
//

import SwiftUI

struct ClearAccountCacheButton: View {
    let account: Account
    @State private var showingConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !failedKinds.isEmpty {
                Label(
                    "Cached \(failedKinds.formatted()) data could not be read. Clear it to download a fresh copy.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
                .accessibilityLabel("Cached data could not be read for \(failedKinds.formatted()).")
            }
            Button(role: .destructive) {
                showingConfirmation = true
            } label: {
                Label("Clear Cached Data…", systemImage: "externaldrive.badge.xmark")
            }
            .buttonStyle(.bordered)
        }
        .confirmationDialog(
            "Clear cached data for \(account.name)?",
            isPresented: $showingConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Cached Data", role: .destructive) {
                AccountsStore.shared.clearCachedData(for: account.id)
                AccessibilityNotification.Announcement(
                    String(localized: "Cached data cleared for \(account.name)")
                ).post()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("PadBuddy will remove downloaded pads, questions, organization, quota, and pad details. "
                + "Your account, favorites, and settings are kept and data reloads when needed.")
        }
        .help("Remove this account's downloaded data without deleting the account.")
    }

    private var failedKinds: [String] {
        CacheLoadDiagnostics.failedKinds(account: account.id)
    }
}
