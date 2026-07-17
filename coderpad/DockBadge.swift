//
//  DockBadge.swift
//  coderpad
//
//  Drives the count on the Dock icon: the active (started) pads the user owns. The
//  user chooses the scope in Settings — the current account, every account, or off
//  (#399). The count is self-clearing, so it needs no read-tracking beyond what the
//  app already maintains.
//

import SwiftUI
#if !os(macOS)
    import UserNotifications
#endif

/// What the app badge counts: nothing, the current account's started pads, or
/// every account's. Persisted by its raw value via `@AppStorage` (#399/#679).
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

/// Owns the app's Dock-badge policy: which accounts' started pads to count (the
/// user's ``DockBadgeScope`` choice) and the migration of the old on/off preference.
/// The count *derivation* lives here; rendering the tile is delegated to
/// `BuddyAppKit`'s `DockBadge.set(count:)`.
enum DockBadgeController {
    @MainActor private static var badgeGeneration = 0
    @MainActor private static var badgeTask: Task<Void, Never>?

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
    /// Reading the sources and rendering the tile both happen on the main actor.
    static func refresh() {
        Task { @MainActor in apply() }
    }

    /// Resolve the count and write the platform badge. A zero count clears the badge,
    /// so "nothing to show" (or the badge being off) leaves a clean icon rather than a
    /// "0".
    @MainActor
    static func apply() {
        badgeGeneration += 1
        let generation = badgeGeneration
        badgeTask?.cancel()
        setPlatformBadge(count: activePadCount(), generation: generation)
    }

    @MainActor
    private static func activePadCount() -> Int {
        let store = AccountsStore.shared
        // The accounts whose started pads the badge counts, per the chosen scope.
        let countedAccounts: [Account]
        switch scope {
        case .off:
            return 0

        case .currentAccount:
            // No single current account means there's nothing to scope to, so clear
            // the badge rather than guess. The store retains the last selection while
            // the combined "All Accounts" view is active, so check the merged flag
            // explicitly - otherwise the badge keeps counting a hidden account (#794).
            guard !store.isMergedView, let current = store.currentAccount else { return 0 }

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
        return PadsCacheStore.shared.padsByAccount.reduce(0) { running, entry in
            let (accountID, pads) = entry
            guard let email = canonicalEmails[accountID] else { return running }

            return running + pads.count(where: {
                $0.status == .active && $0.ownerEmail.canonicalOwnerEmail == email
            })
        }
    }

    @MainActor
    private static func setPlatformBadge(count: Int, generation: Int) {
        #if os(macOS)
            DockBadge.set(count: count)
        #else
            let center = UNUserNotificationCenter.current()
            badgeTask = Task { @MainActor in
                let settings = await center.notificationSettings()
                guard isCurrentBadge(generation) else { return }

                switch settings.authorizationStatus {
                case .notDetermined:
                    guard count > 0 else { return }
                    guard await (try? center.requestAuthorization(options: [.badge])) == true else { return }

                case .denied:
                    return

                default:
                    break
                }

                guard isCurrentBadge(generation) else { return }
                guard await center.notificationSettings().badgeSetting == .enabled else { return }
                guard isCurrentBadge(generation) else { return }

                center.setBadgeCount(count) { error in
                    if let error {
                        print("Failed to update app icon badge: \(error.localizedDescription)")
                    }
                }
            }
        #endif
    }

    @MainActor
    private static func isCurrentBadge(_ generation: Int) -> Bool {
        !Task.isCancelled && generation == badgeGeneration
    }
}
