//
//  SettingsView+BackgroundRefresh.swift
//  coderpad
//

import SwiftUI

extension SettingsView {
    @ViewBuilder
    var backgroundRefreshFailuresSection: some View {
        let refresher = PadsBackgroundRefresher.shared
        let failureIDs = refresher.failuresByAccount.keys.sorted { lhs, rhs in
            accountName(lhs).localizedCaseInsensitiveCompare(accountName(rhs)) == .orderedAscending
        }
        if !failureIDs.isEmpty {
            Section {
                ForEach(failureIDs, id: \.self) { accountID in
                    if let failure = refresher.failuresByAccount[accountID] {
                        LabeledContent(accountName(accountID)) {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(PadsBackgroundRefresher.failureLabel(failure.kind))
                                Text("^[\(failure.consecutiveFailures) consecutive failures](inflect: true)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(failure.lastFailure, format: .relative(presentation: .named))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                Button("Retry All") {
                    Task { await refresher.retryAllFailures() }
                }
            } header: {
                Text("Background refresh")
            } footer: {
                Text("PadBuddy keeps the last downloaded data until a refresh succeeds.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func accountName(_ id: UUID) -> String {
        store.accounts.first(where: { $0.id == id })?.name ?? String(localized: "Removed account")
    }
}
