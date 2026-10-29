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

enum NavigationSessionLoader {
    static func availableSection(from section: AppSection) -> AppSection {
        AppSection.navigable.contains(section) ? section : .pads
    }

    /// A section restored from a scene-storage raw value, or nil when unset or no
    /// longer navigable.
    static func section(fromSceneValue raw: String) -> AppSection? {
        guard let section = AppSection(rawValue: raw),
              AppSection.navigable.contains(section) else { return nil }

        return section
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
        // The session this loader was started for. The account or merged mode can
        // change while the awaits below run (the hosting `.task(id:)` cancels this
        // task, but cancellation only helps where it's checked): a stale loader
        // must not run the health check - which reads the *current* account - for
        // the session that replaced it (#1245), nor keep applying work after the
        // new session began (#1239).
        let session = NavigationSessionKey(accountID: store.currentAccountID, merged: store.isMergedView)
        func sessionStillCurrent() -> Bool {
            !Task.isCancelled
                && session == NavigationSessionKey(accountID: store.currentAccountID,
                                                   merged: store.isMergedView)
        }

        if store.isMergedView {
            let accounts = store.mergeableAccounts
            // Warm inactive merged sections right away - concurrently with directory and
            // health checks - so the first switch can render cached rows instead of spinners.
            async let warmed: Void = prefetchInactiveMergedSections(accounts: accounts, active: section)
            await directory.loadMerged(for: accounts)
            if sessionStillCurrent() {
                await monitor.checkCurrentAccount()
                monitor.start()
            }
            await warmed
        } else if let account = store.currentAccount {
            // Warm the list(s) not currently on screen right away - concurrently with
            // the directory and health checks rather than queued behind them - so the
            // first switch to Pads/Questions has data ready instead of a spinner.
            async let warmed: Void = prefetchInactiveSections(account: account, active: section)
            await directory.load(for: account)
            if sessionStillCurrent() {
                await monitor.checkCurrentAccount()
                monitor.start()
            }
            await warmed
        }
    }

    @MainActor
    static func warmInactiveSections(store: AccountsStore, active section: AppSection, warmQuota: Bool = true) async {
        if store.isMergedView {
            await prefetchInactiveMergedSections(accounts: store.mergeableAccounts, active: section)
        } else if let account = store.currentAccount {
            await prefetchInactiveSections(account: account, active: section, warmQuota: warmQuota)
        }
    }

    /// Fetches inactive merged sections and stores successful results in the shared
    /// per-account caches. The visible section loads itself, so each branch skips its
    /// own active case to avoid duplicate requests.
    private static func prefetchInactiveMergedSections(accounts: [Account], active: AppSection) async {
        await withWarmBudget {
            await performInactiveMergedPrefetch(accounts: accounts, active: active)
        }
    }

    private static func performInactiveMergedPrefetch(accounts: [Account], active: AppSection) async {
        let targets = accounts
            .filter(\.isInterviewFetchEligible)
            .map { (id: $0.id, client: $0.makeClient()) }
        guard !targets.isEmpty else { return }

        // Claimed like the single-account warms: `load` and `warmInactiveSections`
        // can both reach here, and rapid navigation or re-appearance would otherwise
        // start a second identical fan-out over the same accounts (#2679). The key
        // spans the target set, so a warm for a different set of accounts still runs.
        let claim = targets.map(\.id.uuidString).sorted().joined(separator: ",")
        async let pads: Void = active == .pads ? () : withWarmClaim("merged-pads:\(claim)") {
            await prefetchMergedPads(targets)
        }
        async let questions: Void = active == .questions ? () : withWarmClaim("merged-questions:\(claim)") {
            await prefetchMergedQuestions(targets)
        }
        async let quota: Void = active == .quota ? () : withWarmClaim("merged-quota:\(claim)") {
            await prefetchMergedQuota(targets)
        }
        _ = await (pads, questions, quota)
    }

    /// Fetches whichever lists aren't currently displayed and stores them in the
    /// shared caches. The visible section loads itself, so this skips it to avoid
    /// a duplicate request. The pads, questions, and quota warms run concurrently:
    /// they hit independent endpoints, and chaining them made the last section's
    /// warm wait out both earlier fetches for no reason (#1244).
    private static func prefetchInactiveSections(account: Account, active: AppSection, warmQuota: Bool = true) async {
        await withWarmBudget {
            await performInactivePrefetch(account: account, active: active, warmQuota: warmQuota)
        }
    }

    private static func performInactivePrefetch(account: Account, active: AppSection, warmQuota: Bool) async {
        guard account.isInterviewFetchEligible else { return }

        let client = account.makeClient()
        let id = account.id

        async let pads: Void = active == .pads ? () : prefetchPads(id: id, client: client)
        async let questions: Void = active == .questions ? () : prefetchQuestions(id: id, client: client)
        // Warm the quota too, so the sidebar/tab set knows up front whether the plan
        // is unlimited without the user having to open Quota or Organization first.
        async let quota: Void = warmQuota ? prefetchQuota(id: id, client: client) : ()
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
    /// Warm fetches already running, keyed `kind:account`, so overlapping loader
    /// invocations (a session restart racing a section change) don't duplicate
    /// the same expensive list/quota request (#1837). The visible section's own
    /// load is separate by design - the loader always skips the active section.
    @MainActor private static var inFlightWarms: Set<String> = []

    /// The session (chosen account plus combined-view flag) the app is on right now.
    /// Warms capture this when they start and re-check it after their awaits: the
    /// hosting `.task(id:)` cancels on a session change, but a fan-out already in
    /// flight would otherwise keep fetching for — and publishing caches of — a
    /// session the user has already left (#2068). The per-write client check in the
    /// cache stores only catches removed or re-keyed accounts (#754); a plain switch
    /// away leaves the client valid, so the session key is what stops the work.
    @MainActor
    static var currentSession: NavigationSessionKey {
        NavigationSessionKey(accountID: AccountsStore.shared.currentAccountID,
                             merged: AccountsStore.shared.isMergedView)
    }

    /// Wall-clock cap on one inactive-section warm. Warms are pure background work
    /// that shares the connection pool with the section the user is actually looking
    /// at; without a cap, a slow link lets directory/health/pads/questions/quota
    /// warms compete with the visible load indefinitely (#2069). Generous enough
    /// that a healthy fetch never trips it.
    static let warmBudget: Duration = .seconds(30)

    /// Return at the deadline even if a request ignores cancellation. Its slot
    /// remains held until actual completion so repeated timeouts cannot accumulate
    /// an unbounded collection of abandoned warm bodies.
    @MainActor
    static func withWarmBudget(
        _ budget: Duration = warmBudget,
        slots: NavigationWarmSlots = .shared,
        _ body: @escaping @MainActor @Sendable () async -> Void
    ) async {
        guard !Task.isCancelled, let owner = slots.claim() else { return }

        let completion = SingleResume<Bool>()
        let warm = Task {
            defer { slots.release(owner) }
            await body()
            completion.finish(true)
        }
        let watchdog = Task {
            do {
                try await Task.sleep(for: budget)
                warm.cancel()
                completion.finish(false)
            } catch {}
        }
        defer { watchdog.cancel() }
        await withTaskCancellationHandler {
            _ = await withCheckedContinuation { completion.attach($0) }
        } onCancel: {
            warm.cancel()
            completion.finish(false)
        }
    }

    @MainActor
    static func withWarmClaim(_ key: String, _ body: () async -> Void) async {
        guard !inFlightWarms.contains(key) else { return }

        inFlightWarms.insert(key)
        defer { inFlightWarms.remove(key) }
        await body()
    }

    nonisolated static func logPrefetchFailure(_ kind: String, account: UUID, error: any Error) {
        persistenceLogger.info(
            """
            Background \(kind, privacy: .public) warm failed for account \
            \(account.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)
            """
        )
    }
}
