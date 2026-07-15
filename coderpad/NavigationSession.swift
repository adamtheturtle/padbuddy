//
//  NavigationSession.swift
//  coderpad
//

import Foundation
import SwiftUI

/// Restart key for the per-session load task: the chosen account plus whether the
/// combined view is active, so the task re-runs when either changes.
struct NavigationSessionKey: Hashable {
    let accountID: UUID?
    let merged: Bool
}

@ViewBuilder
func navigationStatusBanner(
    store: AccountsStore,
    network: NetworkMonitor,
    monitor: AccountHealthMonitor
) -> some View {
    // Offline takes precedence: when there's no path to CoderPad nothing can
    // be edited regardless of the key, so show the offline banner and skip the
    // now-moot unauthorized one (#321).
    if network.isOffline {
        OfflineBanner()
    } else if !store.isMergedView, let id = store.currentAccountID, monitor.isUnauthorized(id) {
        // In the combined view, per-account fetch failures surface inline in the
        // merged list, so the single-account unauthorized banner is suppressed.
        UnauthorizedBanner(monitor: monitor)
    }
}

enum NavigationSessionLoader {
    static func availableSection(from section: AppSection) -> AppSection {
        AppSection.navigable.contains(section) ? section : .pads
    }

    static func persistedSection(for store: AccountsStore) -> AppSection? {
        let raw: String? = if store.isMergedView {
            UserDefaults.standard.string(forKey: "section.merged")
        } else if let account = store.currentAccount {
            UserDefaults.standard.string(forKey: "section.\(account.id.uuidString)")
        } else {
            nil
        }

        guard let raw,
              let section = AppSection(rawValue: raw),
              AppSection.navigable.contains(section) else { return nil }

        return section
    }

    @MainActor
    static func load(
        store: AccountsStore,
        directory: OrgDirectory,
        monitor: AccountHealthMonitor,
        active section: AppSection
    ) async {
        if store.isMergedView {
            await directory.loadMerged(for: store.mergeableAccounts)
            await monitor.checkCurrentAccount()
            monitor.start()
        } else if let account = store.currentAccount {
            // Warm the list(s) not currently on screen right away - concurrently with
            // the directory and health checks rather than queued behind them - so the
            // first switch to Pads/Questions has data ready instead of a spinner.
            async let warmed: Void = prefetchInactiveSections(account: account, active: section)
            await directory.load(for: account)
            await monitor.checkCurrentAccount()
            monitor.start()
            await warmed
        }
    }

    /// Fetches whichever lists aren't currently displayed and stores them in the
    /// shared caches. The visible section loads itself, so this skips it to avoid
    /// a duplicate request.
    private static func prefetchInactiveSections(account: Account, active: AppSection) async {
        guard account.isMock || !account.apiKey.isEmpty else { return }

        let client = account.makeClient()
        let id = account.id

        if active != .pads {
            var latest: [Pad] = []
            do {
                for try await snapshot in client.listPadsIncrementally() {
                    latest = snapshot
                    PadsCacheStore.shared.set(id, pads: snapshot, persist: false)
                }
                PadsCacheStore.shared.set(id, pads: latest)
            } catch {
                // Partial results still warm the UI; persist whatever arrived.
                if !latest.isEmpty { PadsCacheStore.shared.set(id, pads: latest) }
            }
        }

        if active != .questions, let questions = try? await client.listQuestions(sort: "updated_at,desc") {
            QuestionsCacheStore.shared.set(id, questions: questions)
        }

        // Warm the quota too, so the sidebar/tab set knows up front whether the plan
        // is unlimited without the user having to open Quota or Organization first.
        if let quota = try? await client.quota() {
            QuotaCacheStore.shared.set(id, quota: quota)
        }
    }
}
