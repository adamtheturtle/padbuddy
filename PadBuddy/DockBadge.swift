//
//  DockBadge.swift
//  coderpad
//
//  Drives the count on the Dock icon: the active (started) pads the user owns. The
//  user chooses the scope in Settings — the current account, every account, or off
//  (#399). The count is self-clearing, so it needs no read-tracking beyond what the
//  app already maintains.
//

import os
import SwiftUI
#if os(iOS)
    @preconcurrency import UserNotifications
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

enum BadgeCompletionAction: Equatable {
    case noChange
    case reassertCurrent
    case clearCurrentAfterFailure
}

func badgeCompletionAction(
    requestGeneration: Int, currentGeneration: Int, failed: Bool
) -> BadgeCompletionAction {
    guard requestGeneration == currentGeneration else { return .reassertCurrent }

    return failed ? .clearCurrentAfterFailure : .noChange
}

/// Owns the app's Dock-badge policy: which accounts' started pads to count (the
/// user's ``DockBadgeScope`` choice) and the migration of the old on/off preference.
/// The count *derivation* lives here; rendering the tile is delegated to
/// `BuddyAppKit`'s `DockBadge.set(count:)`.
enum DockBadgeController {
    @MainActor private static var badgeGeneration = 0
    @MainActor private static var desiredBadgeCount = 0
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
        let raw = UserDefaults.standard.string(forKey: Key.scope)
        // An unset key is a fresh install, which defaults to counting every account.
        // A key that is set but unrecognized is corrupt or from a newer version, and
        // falling through to `.allAccounts` there silently exposed a cross-account
        // count the user never chose — so that case fails closed (#2166).
        guard let raw else { return .allAccounts }
        guard let scope = DockBadgeScope(rawValue: raw) else {
            persistenceLogger.error("Unrecognized Dock badge scope; treating the badge as off")
            return .off
        }

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
        // The key's presence is checked with `object(forKey:)` — `bool(forKey:)` alone
        // returns false for a missing key, which would migrate a fresh install to
        // `.off`. The value itself is then read through `bool(forKey:)` rather than
        // `as? Bool`, which missed a value bridged as a number and left the old
        // preference unmigrated (#2169).
        guard defaults.string(forKey: Key.scope) == nil,
              defaults.object(forKey: Key.enabled) != nil else { return }

        let wasEnabled = defaults.bool(forKey: Key.enabled)

        defaults.set((wasEnabled ? DockBadgeScope.allAccounts : .off).rawValue, forKey: Key.scope)
    }

    /// Recompute the badge and apply it on the main thread. Cheap and idempotent, so
    /// it's safe to call after any pad-cache change or when the preference is edited.
    /// Reading the sources and rendering the tile both happen on the main actor.
    static func refresh() {
        Task { @MainActor in
            // Bursts of cache writes each used to enqueue their own main-actor task,
            // all of which ran and were then coalesced by the generation counter in
            // `apply`. Replacing a pending refresh instead means one task per burst
            // (#2168). `apply` still guards the platform write, since the badge work
            // it starts is asynchronous.
            refreshTask?.cancel()
            let task = Task { @MainActor in
                guard !Task.isCancelled else { return }

                apply()
            }
            refreshTask = task
            await task.value
        }
    }

    /// The pending refresh, replaced rather than stacked. See `refresh()`.
    @MainActor private static var refreshTask: Task<Void, Never>?

    /// Resolve the count and write the platform badge. A zero count clears the badge,
    /// so "nothing to show" (or the badge being off) leaves a clean icon rather than a
    /// "0".
    @MainActor
    static func apply() {
        badgeGeneration += 1
        let generation = badgeGeneration
        let count = activePadCount()
        desiredBadgeCount = count
        badgeTask?.cancel()
        setPlatformBadge(count: count, generation: generation)
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
        // per account (case- and whitespace-normalized; see `String.canonicalOwnerEmail`)
        // while preserving the exact mailbox local part.
        let canonicalEmails = Dictionary(
            countedAccounts
                .filter { !$0.userEmail.isEmpty }
                .map { ($0.id, $0.userEmail.canonicalOwnerEmail) },
            uniquingKeysWith: { first, _ in first }
        )
        let padsCache = PadsCacheStore.shared
        return countedAccounts.reduce(0) { running, account in
            let accountID = account.id
            guard let email = canonicalEmails[accountID] else { return running }

            // `get` consults the persisted snapshot once when this account has not
            // yet been loaded in memory. Reducing only `padsByAccount` made the
            // all-account badge incomplete after a cold launch until every account
            // happened to visit a pad screen (#1135, #1139).
            let pads = padsCache.get(accountID)

            // Counted per distinct pad id: a cache seed overlapping a fresh page can
            // leave the same pad twice in one account's rows, which inflated the badge
            // (#2172, the same duplication #2620 repaired elsewhere).
            var seenPadIDs = Set<String>()
            return running + pads.count(where: {
                guard seenPadIDs.insert($0.id).inserted else { return false }

                // Status first: it's a cheap enum compare, and it rejects the great
                // majority of pads before the canonicalization — which trims and
                // lowercases into a fresh String, and used to run for every pad of
                // every account on every badge refresh (#2436).
                guard $0.status == .active else { return false }

                return $0.ownerEmail == email || $0.ownerEmail.canonicalOwnerEmail == email
            })
        }
    }

    @MainActor
    private static func setPlatformBadge(count: Int, generation: Int) {
        #if os(macOS)
            DockBadge.set(count: count)
        #elseif os(iOS)
            let center = UNUserNotificationCenter.current()
            badgeTask = Task { @MainActor in
                // Clearing takes no permission and is never unwanted, so a zero count
                // skips the authorization checks entirely and just writes it. Going
                // through them meant turning the badge off — or being denied after
                // once being granted — returned early and left the last count sitting
                // on the icon (#2580).
                guard count > 0 else {
                    writeBadge(count: 0, generation: generation, center: center)
                    await requestBadgePermissionIfNeeded(center: center)
                    return
                }

                let settings = await center.notificationSettings()
                guard isCurrentBadge(generation) else { return }

                switch settings.authorizationStatus {
                case .notDetermined:
                    guard await (try? center.requestAuthorization(options: [.badge])) == true else {
                        // Permission unavailable after the prompt (or the request failed):
                        // clear any count written while badges were previously allowed (#4689).
                        writeBadge(count: 0, generation: generation, center: center)
                        return
                    }

                case .denied:
                    // A prior granted count can remain on the icon after the user denies
                    // badges; clearing needs no permission (#4689).
                    writeBadge(count: 0, generation: generation, center: center)
                    return

                default:
                    break
                }

                guard isCurrentBadge(generation) else { return }
                guard await center.notificationSettings().badgeSetting == .enabled else {
                    writeBadge(count: 0, generation: generation, center: center)
                    return
                }
                guard isCurrentBadge(generation) else { return }

                writeBadge(count: count, generation: generation, center: center)
            }
        #else
            _ = count
            _ = generation
        #endif
    }

    #if os(iOS)
        /// Resolves an undetermined badge permission while the badge is wanted but the
        /// count is zero.
        ///
        /// Clearing needs no permission, so this path used to return without ever
        /// asking — a user could enable badges, see nothing, and only meet the prompt
        /// whenever a pad next went active, by which point the request has no visible
        /// connection to the setting they changed (#2171). Only asks when the badge is
        /// actually wanted, so turning it off never prompts.
        @MainActor
        private static func requestBadgePermissionIfNeeded(center: UNUserNotificationCenter) async {
            guard scope != .off else { return }
            guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }

            _ = try? await center.requestAuthorization(options: [.badge])
        }

        @MainActor
        private static func writeBadge(count: Int, generation: Int, center: UNUserNotificationCenter) {
            center.setBadgeCount(count) { error in
                Task { @MainActor in
                    switch badgeCompletionAction(
                        requestGeneration: generation,
                        currentGeneration: badgeGeneration,
                        failed: error != nil
                    ) {
                    case .noChange:
                        break

                    case .reassertCurrent:
                        // The older system write completed after a newer request was
                        // issued. Queue the desired current value again so completion
                        // order cannot leave the icon stale (#1136).
                        center.setBadgeCount(desiredBadgeCount)

                    case .clearCurrentAfterFailure:
                        if let error {
                            persistenceLogger.error(
                                "Failed to update app icon badge: \(error.localizedDescription, privacy: .private)"
                            )
                        }
                        center.setBadgeCount(0)
                    }
                }
            }
        }
    #endif

    @MainActor
    private static func isCurrentBadge(_ generation: Int) -> Bool {
        !Task.isCancelled && generation == badgeGeneration
    }
}
