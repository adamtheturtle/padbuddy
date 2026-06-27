//
//  DockBadge.swift
//  coderpad
//
//  Drives the count on the Dock icon: the active (started) pads the user owns. The
//  user chooses the scope in Settings — the current account, every account, or off
//  (#399). The count is self-clearing, so it needs no read-tracking beyond what the
//  app already maintains.
//

#if os(macOS)
    import AppKit
#endif
import SwiftUI

/// What the Dock badge counts: nothing, the current account's started pads, or
/// every account's. Persisted by its raw value via `@AppStorage` (#399).
enum DockBadgeScope: String, CaseIterable, Identifiable {
    case off
    case currentAccount
    case allAccounts

    var id: String {
        rawValue
    }

    var label: LocalizedStringKey {
        switch self {
        case .off: "Off"
        case .currentAccount: "Current account"
        case .allAccounts: "All accounts"
        }
    }
}

enum DockBadge {
    enum Key {
        static let scope = "general.dockBadgeScope"
        /// The old on/off Bool, kept only so a saved choice can be migrated into
        /// `scope` once (see ``migrateScopeIfNeeded``).
        static let enabled = "general.dockBadgeEnabled"
    }

    /// The chosen badge scope, defaulting to ``DockBadgeScope/allAccounts`` for the
    /// unset case — matching the `@AppStorage` default in Settings so the two never
    /// disagree, and preserving the old default (badge on, counting every account).
    static var scope: DockBadgeScope {
        guard let raw = UserDefaults.standard.string(forKey: Key.scope),
              let scope = DockBadgeScope(rawValue: raw) else { return .allAccounts }

        return scope
    }

    /// One-time migration of the old on/off `enabled` Bool to the new ``scope``
    /// choice, run at launch. The Bool defaulted to `true` (count across every
    /// account), so a missing/true value becomes `.allAccounts` and an explicit
    /// `false` becomes `.off` — a user who'd switched the badge off keeps it off.
    /// Only writes when the new key is unset and the old one exists, so it's a no-op
    /// on every later launch and for fresh installs.
    static func migrateScopeIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: Key.scope) == nil,
              let wasEnabled = defaults.object(forKey: Key.enabled) as? Bool else { return }

        defaults.set((wasEnabled ? DockBadgeScope.allAccounts : .off).rawValue, forKey: Key.scope)
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
        // iOS has no Dock, so there's nothing to render. The scope/preference logic
        // above still compiles and works; only the tile rendering is macOS-only.
        #if os(macOS)
            let store = AccountsStore.shared
            // The accounts whose started pads the badge counts, per the chosen scope.
            let countedAccounts: [Account]
            switch scope {
            case .off:
                NSApp.dockTile.badgeLabel = nil
                return

            case .currentAccount:
                // No single current account (e.g. the combined "All Accounts" view) means
                // there's nothing to scope to, so clear the badge rather than guess.
                guard let current = store.currentAccount else {
                    NSApp.dockTile.badgeLabel = nil
                    return
                }

                countedAccounts = [current]

            case .allAccounts:
                countedAccounts = store.accounts
            }

            // Only the user's own started pads, scoped per account: ownership is compared
            // against each account's configured email (matching `MergedPadsView.isMine`),
            // so other interviewers' live pads don't count. Emails are canonicalized once
            // per account (case- and plus-addressing-folded; see `String.canonicalOwnerEmail`)
            // so a pad owned via a sub-address alias still counts as the account user's.
            let canonicalEmails = Dictionary(
                countedAccounts
                    .filter { !$0.userEmail.isEmpty }
                    .map { ($0.id, $0.userEmail.canonicalOwnerEmail) },
                uniquingKeysWith: { first, _ in first }
            )
            let activePadTotal = PadsCacheStore.shared.padsByAccount.reduce(0) { running, entry in
                let (accountID, pads) = entry
                guard let email = canonicalEmails[accountID] else { return running }

                return running + pads.count(where: {
                    $0.status == .active && $0.ownerEmail.canonicalOwnerEmail == email
                })
            }
            NSApp.dockTile.badgeLabel = activePadTotal > 0 ? "\(activePadTotal)" : nil
            // Force the tile to redraw. Setting `badgeLabel` alone doesn't always refresh a
            // tile that's already on screen, so the new count can otherwise go unshown.
            NSApp.dockTile.display()
        #endif
    }
}
