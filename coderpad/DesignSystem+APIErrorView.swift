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
                    .prominentGlassButtonStyle()
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
                        .prominentGlassButtonStyle()
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
                        .prominentGlassButtonStyle()
                }
            }
        }
    }
}
