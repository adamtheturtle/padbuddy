//
//  NavigationSession.swift
//  coderpad
//

import Foundation
import os
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
            let accounts = store.mergeableAccounts
            // Warm inactive merged sections right away - concurrently with directory and
            // health checks - so the first switch can render cached rows instead of spinners.
            async let warmed: Void = prefetchInactiveMergedSections(accounts: accounts, active: section)
            await directory.loadMerged(for: accounts)
            await monitor.checkCurrentAccount()
            monitor.start()
            await warmed
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

    @MainActor
    static func warmInactiveSections(store: AccountsStore, active section: AppSection) async {
        if store.isMergedView {
            await prefetchInactiveMergedSections(accounts: store.mergeableAccounts, active: section)
        } else if let account = store.currentAccount {
            await prefetchInactiveSections(account: account, active: section)
        }
    }

    /// Fetches inactive merged sections and stores successful results in the shared
    /// per-account caches. The visible section loads itself, so each branch skips its
    /// own active case to avoid duplicate requests.
    private static func prefetchInactiveMergedSections(accounts: [Account], active: AppSection) async {
        let targets = accounts
            .filter { $0.isMock || !$0.apiKey.isEmpty }
            .map { (id: $0.id, client: $0.makeClient()) }
        guard !targets.isEmpty else { return }

        async let pads: Void = active == .pads ? () : prefetchMergedPads(targets)
        async let questions: Void = active == .questions ? () : prefetchMergedQuestions(targets)
        async let quota: Void = active == .quota ? () : prefetchMergedQuota(targets)
        _ = await (pads, questions, quota)
    }

    private static func prefetchMergedPads(_ targets: [(id: UUID, client: CoderPadClient)]) async {
        await withTaskGroup(of: (UUID, [Pad]?).self) { group in
            for target in targets {
                group.addTask {
                    do {
                        let pads = try await target.client.listPads(sort: "updated_at,desc")
                        return (target.id, pads)
                    } catch {
                        return (target.id, nil)
                    }
                }
            }

            let clientsByID = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0.client) })
            for await (id, pads) in group {
                if let pads, let client = clientsByID[id] {
                    PadsCacheStore.shared.set(id, pads: pads, via: client)
                }
            }
        }
    }

    private static func prefetchMergedQuestions(_ targets: [(id: UUID, client: CoderPadClient)]) async {
        await withTaskGroup(of: (UUID, [Question]?).self) { group in
            for target in targets {
                group.addTask {
                    do {
                        let questions = try await target.client.listQuestions(sort: "updated_at,desc")
                        return (target.id, questions)
                    } catch {
                        return (target.id, nil)
                    }
                }
            }

            let clientsByID = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0.client) })
            for await (id, questions) in group {
                if let questions, let client = clientsByID[id] {
                    QuestionsCacheStore.shared.set(id, questions: questions, via: client)
                }
            }
        }
    }

    private static func prefetchMergedQuota(_ targets: [(id: UUID, client: CoderPadClient)]) async {
        await withTaskGroup(of: (UUID, Quota?).self) { group in
            for target in targets {
                group.addTask {
                    do {
                        let quota = try await target.client.quota()
                        return (target.id, quota)
                    } catch {
                        return (target.id, nil)
                    }
                }
            }

            let clientsByID = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0.client) })
            for await (id, quota) in group {
                if let quota, let client = clientsByID[id] {
                    QuotaCacheStore.shared.set(id, quota: quota, via: client)
                }
            }
        }
    }

    /// Fetches whichever lists aren't currently displayed and stores them in the
    /// shared caches. The visible section loads itself, so this skips it to avoid
    /// a duplicate request. The pads, questions, and quota warms run concurrently:
    /// they hit independent endpoints, and chaining them made the last section's
    /// warm wait out both earlier fetches for no reason (#1244).
    private static func prefetchInactiveSections(account: Account, active: AppSection) async {
        guard account.isMock || !account.apiKey.isEmpty else { return }

        let client = account.makeClient()
        let id = account.id

        async let pads: Void = active == .pads ? () : prefetchPads(id: id, client: client)
        async let questions: Void = active == .questions ? () : prefetchQuestions(id: id, client: client)
        // Warm the quota too, so the sidebar/tab set knows up front whether the plan
        // is unlimited without the user having to open Quota or Organization first.
        async let quota: Void = prefetchQuota(id: id, client: client)
        _ = await (pads, questions, quota)
    }

    // On a mid-stream paging failure, the partial list must stay memory-only
    // (persist: false): the streamed snapshots already warmed the UI, and running
    // the persist cascade would commit a truncated list as authoritative — writing
    // it to disk, reconciling the unfetched items OUT of Spotlight, and shrinking
    // the widget/badge/MCP counts — while silently replacing the previous complete
    // snapshot (#1025, #1039). Only a completed stream persists. Failures are
    // logged (privacy-safe: account id + error text) rather than swallowed, so a
    // consistently failing warm is diagnosable from Console (#1243).
    private static func prefetchPads(id: UUID, client: CoderPadClient) async {
        var latest: [Pad] = []
        do {
            for try await snapshot in client.listPadsIncrementally() {
                latest = snapshot
                PadsCacheStore.shared.set(id, pads: snapshot, via: client, persist: false)
            }
            PadsCacheStore.shared.set(id, pads: latest, via: client)
        } catch {
            logPrefetchFailure("pads", account: id, error: error)
            if !latest.isEmpty { PadsCacheStore.shared.set(id, pads: latest, via: client, persist: false) }
        }
    }

    private static func prefetchQuestions(id: UUID, client: CoderPadClient) async {
        var latest: [Question] = []
        do {
            for try await snapshot in client.listQuestionsIncrementally() {
                latest = snapshot
                QuestionsCacheStore.shared.set(id, questions: snapshot, via: client, persist: false)
            }
            QuestionsCacheStore.shared.set(id, questions: latest, via: client)
        } catch {
            logPrefetchFailure("questions", account: id, error: error)
            if !latest.isEmpty {
                QuestionsCacheStore.shared.set(id, questions: latest, via: client, persist: false)
            }
        }
    }

    private static func prefetchQuota(id: UUID, client: CoderPadClient) async {
        do {
            let quota = try await client.quota()
            QuotaCacheStore.shared.set(id, quota: quota, via: client)
        } catch {
            logPrefetchFailure("quota", account: id, error: error)
        }
    }

    private static func logPrefetchFailure(_ kind: String, account: UUID, error: any Error) {
        persistenceLogger.info(
            """
            Background \(kind, privacy: .public) warm failed for account \
            \(account.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)
            """
        )
    }
}
