//
//  DockBadge.swift
//  coderpad
//
//  Drives the count on the Dock icon. When enabled, it counts the active (started)
//  pads the user owns across every account — a live interview of theirs in progress.
//  The count is self-clearing, so it needs no read-tracking beyond what the app
//  already maintains. The user can turn it off entirely in Settings.
//

import AppKit

enum DockBadge {
    enum Key {
        static let enabled = "general.dockBadgeEnabled"
    }

    /// Whether the badge is shown, defaulting to `true` for the unset case — matching
    /// the `@AppStorage` default in Settings so the two never disagree.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Key.enabled) as? Bool ?? true
    }

    /// Recompute the badge and apply it on the main thread. Cheap and idempotent, so
    /// it's safe to call after any pad-cache change or when the preference is edited.
    /// Reading the sources and touching `NSApp.dockTile` both happen on the main actor.
    static func refresh() {
        Task { @MainActor in apply() }
    }

    /// Resolve the count and write the badge. A nil label removes the badge entirely,
    /// so "nothing to show" (or the badge being off) leaves a clean icon rather than a "0".
    @MainActor
    static func apply() {
        guard isEnabled else {
            NSApp.dockTile.badgeLabel = nil
            return
        }
        // Only the user's own started pads, scoped per account: ownership is compared
        // against each account's configured email (matching `MergedPadsView.isMine`),
        // so other interviewers' live pads don't count.
        let emails = Dictionary(
            AccountsStore.shared.accounts.map { ($0.id, $0.userEmail) },
            uniquingKeysWith: { first, _ in first }
        )
        let count = PadsCacheStore.shared.padsByAccount.reduce(0) { running, entry in
            let (accountID, pads) = entry
            guard let email = emails[accountID] else { return running }
            return running + pads.filter {
                $0.status == .active && $0.ownerEmail.caseInsensitiveCompare(email) == .orderedSame
            }.count
        }
        NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
    }
}
