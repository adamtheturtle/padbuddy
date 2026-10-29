//
//  ClearAccountCacheButton.swift
//  coderpad
//

import SwiftUI

struct ClearAccountCacheButton: View {
    let account: Account
    @State private var showingConfirmation = false
    @State private var cacheByteCount: Int64?
    @State private var isClearing = false

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
            if let cacheByteCount {
                Text("Downloaded data: \(ByteCountFormatter.string(fromByteCount: cacheByteCount, countStyle: .file))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button(role: .destructive) {
                showingConfirmation = true
            } label: {
                Label("Clear Cached Data…", systemImage: "externaldrive.badge.xmark")
            }
            .buttonStyle(.bordered)
            .disabled(isClearing)
        }
        .confirmationDialog(
            "Clear cached data for \(account.name)?",
            isPresented: $showingConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Cached Data", role: .destructive) {
                guard !isClearing else { return }

                isClearing = true
                Task {
                    defer { isClearing = false }
                    await AccountsStore.shared.clearCachedData(for: account.id)
                    cacheByteCount = 0
                    AccessibilityNotification.Announcement(
                        String(localized: "Cached data cleared for \(account.name)")
                    ).post()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("PadBuddy will remove downloaded pads, questions, organization, quota, and pad details. "
                + "Your account, favorites, and settings are kept and data reloads when needed.")
        }
        .help("Remove this account's downloaded data without deleting the account.")
        .task(id: account.id) {
            let accountID = account.id
            cacheByteCount = await Task.detached(priority: .utility) {
                CacheDisk.diskUsage(account: accountID)
            }.value
        }
    }

    private var failedKinds: [String] {
        CacheLoadDiagnostics.failedKinds(account: account.id)
    }
}
