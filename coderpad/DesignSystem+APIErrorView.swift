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
    /// The account whose request failed, when the caller knows it. The
    /// unauthorized action edits *this* account; falling back to the globally
    /// current one sent users to the wrong editor when another account's fetch
    /// failed in a merged load (#1698).
    var accountID: UUID?
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
                        navigation.accountToEdit = accountID ?? AccountsStore.shared.currentAccountID
                        openSettings()
                    }
                    .buttonStyle(.glassProminent)
                    if let onRetry {
                        RetryCooldownButton(title: "Retry", action: onRetry)
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
                    Button("Open Settings") {
                        // Land on the add-account editor the copy promises, not
                        // whichever Settings page was last open (#1699).
                        let navigation = SettingsNavigation.shared
                        navigation.selectedTab = .accounts
                        navigation.startAddingAccount = true
                        openSettings()
                    }
                    .buttonStyle(.glassProminent)
                    GetAPIKeyLink()
                }
            }
        } else {
            ContentUnavailableView {
                Label("Something went wrong", systemImage: "exclamationmark.triangle")
            } description: {
                // Bounded: server-provided diagnostic text can be arbitrarily
                // long, and the empty state must stay a readable summary (#1700).
                Text(String(error.localizedDescription.prefix(300)))
            } actions: {
                if let onRetry {
                    RetryCooldownButton(title: "Retry", action: onRetry)
                        .buttonStyle(.glassProminent)
                }
            }
        }
    }
}

/// A retry button that ignores rapid re-taps: the closures behind these retries
/// start fetches with no in-progress reporting, and hammering the button could
/// stack concurrent reloads racing to replace the same data (#1701). The
/// underlying reloads are generation-guarded too; this just stops the button
/// from initiating the race.
struct RetryCooldownButton: View {
    let title: LocalizedStringKey
    let action: () -> Void
    @State private var coolingDown = false

    var body: some View {
        Button(title) {
            guard !coolingDown else { return }

            coolingDown = true
            action()
            Task {
                try? await Task.sleep(for: .seconds(2))
                coolingDown = false
            }
        }
        .disabled(coolingDown)
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
            RetryCooldownButton(title: "Try Again", action: retry)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.orange.opacity(0.12),
            in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        )
    }
}
