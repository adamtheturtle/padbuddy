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
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, Spacing.bannerH)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
    } else if let id = store.currentAccountID, monitor.isUnauthorized(id),
              !suppressesUnauthorizedBanner(store: store, section: section) {
        UnauthorizedBanner(monitor: monitor)
    }
}

/// Whether the merged list mounted for `section` reports per-account failures
/// itself, making the single-account banner redundant.
private func suppressesUnauthorizedBanner(store: AccountsStore, section: AppSection) -> Bool {
    guard store.isMergedView else { return false }

    return section == .pads || section == .questions
}
