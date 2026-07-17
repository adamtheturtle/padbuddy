//
//  DesignSystem+APIErrorView.swift
//  coderpad
//
//  Split out of DesignSystem+Org.swift to keep each file under the length limit.
//

import SwiftUI

// MARK: - APIErrorView

struct APIErrorView: View {
    let error: any Error
    var onRetry: (() -> Void)?
    @Environment(\.openAppSettings) private var openSettings

    var body: some View {
        if let api = error as? CoderPadError, api.isUnauthorized {
            ContentUnavailableView {
                Label("Key not authorized", systemImage: "lock.shield")
            } actions: {
                VStack(spacing: 8) {
                    Button("Open Settings") {
                        let navigation = SettingsNavigation.shared
                        navigation.selectedTab = .accounts
                        navigation.accountToEdit = AccountsStore.shared.currentAccountID
                        openSettings()
                    }
                    .buttonStyle(.glassProminent)
                    if let onRetry {
                        Button("Retry", action: onRetry)
                    }
                }
            }
        } else if let api = error as? CoderPadError, case .missingAPIKey = api {
            ContentUnavailableView {
                Label("No API key", systemImage: "key")
            } description: {
                Text("Add an account in Settings to start using the app.")
            } actions: {
                VStack(spacing: 8) {
                    Button("Open Settings") { openSettings() }
                        .buttonStyle(.glassProminent)
                    GetAPIKeyLink()
                }
            }
        } else {
            ContentUnavailableView {
                Label("Something went wrong", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error.localizedDescription)
            } actions: {
                if let onRetry {
                    Button("Retry", action: onRetry)
                        .buttonStyle(.glassProminent)
                }
            }
        }
    }
}

/// A compact banner for a refresh that failed while previously loaded data is
/// still on screen (#799/#800): the stale data stays visible but is explicitly
/// marked out of date, with the error and a retry.
struct StaleRefreshBanner: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Couldn't refresh - showing the last loaded data.")
                    .font(.callout.weight(.medium))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Button("Try Again", action: retry)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.orange.opacity(0.12),
            in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        )
    }
}
