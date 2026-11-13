//
//  NavigationStatusBanner.swift
//  coderpad
//
//  The single status banner shown above the main split, split from
//  NavigationSession.swift to keep that file under the file-length limit.
//

import SwiftUI

/// The one status banner shown above the split, if any.
///
/// `section` decides whether the merged view can be trusted to report an
/// unauthorized account itself: only the merged pad and question lists carry the
/// per-account error bar that made suppressing this banner reasonable. On Quota or
/// Screen there is no such bar, so hiding it left a rejected key with nothing to
/// announce it at all (#2676).
@ViewBuilder
func navigationStatusBanner(
    store: AccountsStore,
    network: NetworkMonitor,
    monitor: AccountHealthMonitor,
    section: AppSection
) -> some View {
    // A failed Keychain write outranks everything: the user's account changes
    // will silently revert on relaunch unless they act, and neither network nor
    // key state fixes that (#770).
    if store.persistenceFailed {
        AccountPersistenceBanner(store: store)
    } else if network.isOffline {
        // Offline takes precedence over the key state: when there's no path to
        // CoderPad nothing can be edited regardless of the key, so show the
        // offline banner and skip the now-moot unauthorized one (#321).
        OfflineBanner()
    } else if NetworkConstraintMonitor.shared.isConstrained {
        Label(
            "Low Data Mode is active. Refreshes may be limited.",
            systemImage: "wifi.exclamationmark"
        )
        .font(.caption.weight(.medium))
        .foregroundStyle(lowDataModeBannerForeground)
        .padding(.horizontal, Spacing.bannerH)
        .padding(.vertical, lowDataModeBannerVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(lowDataModeBannerBackground)
    } else if showsNavigationCredentialBanner(isMergedView: store.isMergedView, section: section),
              let account = store.currentAccount,
              PadsBackgroundRefresher.shared.failuresByAccount[account.id]?.kind == .unauthorized {
        BackgroundCredentialBanner(account: account)
    } else if let id = store.currentAccountID, monitor.isUnauthorized(id),
              showsNavigationCredentialBanner(isMergedView: store.isMergedView, section: section) {
        UnauthorizedBanner(monitor: monitor)
    }
}

private var lowDataModeBannerForeground: AnyShapeStyle {
    #if os(visionOS)
        AnyShapeStyle(Color.orange.opacity(0.92))
    #else
        AnyShapeStyle(.secondary)
    #endif
}

private var lowDataModeBannerBackground: Color {
    #if os(visionOS)
        Color.orange.opacity(0.10)
    #else
        Color.orange.opacity(0.12)
    #endif
}

private var lowDataModeBannerVerticalPadding: CGFloat {
    #if os(visionOS)
        6
    #else
        8
    #endif
}

private struct BackgroundCredentialBanner: View {
    let account: Account
    @Environment(\.openAppSettings) private var openSettings

    var body: some View {
        HStack {
            Label(rejectedAPIKeyMessage(for: [account]),
                  systemImage: "key.slash")
            Spacer()
            Button("Fix in Settings") {
                SettingsNavigation.shared.selectedTab = .accounts
                SettingsNavigation.shared.accountToEdit = account.id
                openSettings()
            }
        }
        .padding(.horizontal, Spacing.bannerH)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.18))
    }
}

/// Merged pad and question lists own the credential warning for every account.
/// Apply the same rule to background refresh and health-check failures.
func showsNavigationCredentialBanner(isMergedView: Bool, section: AppSection) -> Bool {
    !isMergedView || (section != .pads && section != .questions)
}
