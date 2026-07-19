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
        let targets = accounts
            .filter { $0.isMock || !$0.apiKey.isEmpty }
            .map { (id: $0.id, client: $0.makeClient()) }
        guard !targets.isEmpty else { return }

        async let pads: Void = active == .pads ? () : prefetchMergedPads(targets)
        async let questions: Void = active == .questions ? () : prefetchMergedQuestions(targets)
        async let quota: Void = active == .quota ? () : prefetchMergedQuota(targets)
        _ = await (pads, questions, quota)
    }

    /// How many accounts one merged warm fetches at a time: a large account set
    /// must not fan out one request per account all at once (#1834).
    private static let mergedPrefetchWidth = 4

    private static func prefetchMergedPads(_ targets: [(id: UUID, client: CoderPadClient)]) async {
        // Per-account write tokens captured before the fetches begin: a slow warm
        // that completes after a fresher (user-initiated) write must not replace
        // it (#1242).
        let tokens = Dictionary(uniqueKeysWithValues: targets.map {
            ($0.id, PadsCacheStore.shared.writeGeneration[$0.id] ?? 0)
        })
        await withTaskGroup(of: (UUID, [Pad]?).self) { group in
            var iterator = targets.makeIterator()
            func addNext() {
                guard let target = iterator.next() else { return }

                group.addTask {
                    do {
                        let pads = try await target.client.listPads(sort: "updated_at,desc")
                        return (target.id, pads)
                    } catch {
                        // Logged, not swallowed: a quietly incomplete warm should be
                        // diagnosable from Console (#1838); the merged views surface
                        // their own per-account errors on their real loads.
                        logPrefetchFailure("merged pads", account: target.id, error: error)
                        return (target.id, nil)
                    }
                }
            }
            for _ in 0 ..< mergedPrefetchWidth {
                addNext()
            }

            let clientsByID = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0.client) })
            for await (id, pads) in group {
                addNext()
                if let pads, let client = clientsByID[id],
                   (PadsCacheStore.shared.writeGeneration[id] ?? 0) == tokens[id] {
                    PadsCacheStore.shared.set(id, pads: pads, via: client)
                }
            }
        }
    }

    private static func prefetchMergedQuestions(_ targets: [(id: UUID, client: CoderPadClient)]) async {
        // See prefetchMergedPads for the write-token rationale (#1242).
        let tokens = Dictionary(uniqueKeysWithValues: targets.map {
            ($0.id, QuestionsCacheStore.shared.writeGeneration[$0.id] ?? 0)
        })
        await withTaskGroup(of: (UUID, [Question]?).self) { group in
            var iterator = targets.makeIterator()
            func addNext() {
                guard let target = iterator.next() else { return }

                group.addTask {
                    do {
                        let questions = try await target.client.listQuestions(sort: "updated_at,desc")
                        return (target.id, questions)
                    } catch {
                        logPrefetchFailure("merged questions", account: target.id, error: error)
                        return (target.id, nil)
                    }
                }
            }
            for _ in 0 ..< mergedPrefetchWidth {
                addNext()
            }

            let clientsByID = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0.client) })
            for await (id, questions) in group {
                addNext()
                if let questions, let client = clientsByID[id],
                   (QuestionsCacheStore.shared.writeGeneration[id] ?? 0) == tokens[id] {
                    QuestionsCacheStore.shared.set(id, questions: questions, via: client)
                }
            }
        }
    }

    private static func prefetchMergedQuota(_ targets: [(id: UUID, client: CoderPadClient)]) async {
        await withTaskGroup(of: (UUID, Quota?).self) { group in
            var iterator = targets.makeIterator()
            func addNext() {
                guard let target = iterator.next() else { return }

                group.addTask {
                    do {
                        let quota = try await target.client.quota()
                        return (target.id, quota)
                    } catch {
                        logPrefetchFailure("merged quota", account: target.id, error: error)
                        return (target.id, nil)
                    }
                }
            }
            for _ in 0 ..< mergedPrefetchWidth {
                addNext()
            }

            let clientsByID = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0.client) })
            for await (id, quota) in group {
                addNext()
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
    private static func prefetchInactiveSections(account: Account, active: AppSection, warmQuota: Bool = true) async {
        guard account.isMock || !account.apiKey.isEmpty else { return }

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

    @MainActor
    private static func withWarmClaim(_ key: String, _ body: () async -> Void) async {
        guard !inFlightWarms.contains(key) else { return }

        inFlightWarms.insert(key)
        defer { inFlightWarms.remove(key) }
        await body()
    }

    private static func prefetchPads(id: UUID, client: CoderPadClient) async {
        await withWarmClaim("pads:\(id.uuidString)") {
            await performPadsPrefetch(id: id, client: client)
        }
    }

    private static func performPadsPrefetch(id: UUID, client: CoderPadClient) async {
        // Write-token coordination (#1242): every write re-checks that no OTHER
        // writer (a user-initiated reload finishing after this warm began) touched
        // the account since this warm's previous write. When one did, the warm
        // stops writing - the fresher result wins - rather than replacing it.
        var token = PadsCacheStore.shared.writeGeneration[id] ?? 0
        func writeIfCurrent(_ pads: [Pad], persist: Bool) {
            guard (PadsCacheStore.shared.writeGeneration[id] ?? 0) == token else { return }

            PadsCacheStore.shared.set(id, pads: pads, via: client, persist: persist)
            token = PadsCacheStore.shared.writeGeneration[id] ?? 0
        }

        // Progressive snapshots only warm a COLD cache: replacing an already
        // complete list page by page would leave a truncated list in memory when
        // a later page fails (#1836). A warm cache is replaced only by the final,
        // complete result.
        let hadCompleteList = !PadsCacheStore.shared.cached(id).isEmpty
        var latest: [Pad] = []
        do {
            for try await snapshot in client.listPadsIncrementally() {
                latest = snapshot
                if !hadCompleteList { writeIfCurrent(snapshot, persist: false) }
            }
            writeIfCurrent(latest, persist: true)
        } catch {
            logPrefetchFailure("pads", account: id, error: error)
            if !hadCompleteList, !latest.isEmpty { writeIfCurrent(latest, persist: false) }
        }
    }

    private static func prefetchQuestions(id: UUID, client: CoderPadClient) async {
        await withWarmClaim("questions:\(id.uuidString)") {
            await performQuestionsPrefetch(id: id, client: client)
        }
    }

    private static func performQuestionsPrefetch(id: UUID, client: CoderPadClient) async {
        // See performPadsPrefetch for the write-token rationale (#1242).
        var token = QuestionsCacheStore.shared.writeGeneration[id] ?? 0
        func writeIfCurrent(_ questions: [Question], persist: Bool) {
            guard (QuestionsCacheStore.shared.writeGeneration[id] ?? 0) == token else { return }

            QuestionsCacheStore.shared.set(id, questions: questions, via: client, persist: persist)
            token = QuestionsCacheStore.shared.writeGeneration[id] ?? 0
        }

        // See performPadsPrefetch: progressive writes only warm a cold cache (#1836).
        let hadCompleteList = !QuestionsCacheStore.shared.cached(id).isEmpty
        var latest: [Question] = []
        do {
            for try await snapshot in client.listQuestionsIncrementally() {
                latest = snapshot
                if !hadCompleteList { writeIfCurrent(snapshot, persist: false) }
            }
            writeIfCurrent(latest, persist: true)
        } catch {
            logPrefetchFailure("questions", account: id, error: error)
            if !hadCompleteList, !latest.isEmpty {
                writeIfCurrent(latest, persist: false)
            }
        }
    }

    private static func prefetchQuota(id: UUID, client: CoderPadClient) async {
        await withWarmClaim("quota:\(id.uuidString)") {
            do {
                let quota = try await client.quota()
                QuotaCacheStore.shared.set(id, quota: quota, via: client)
            } catch {
                logPrefetchFailure("quota", account: id, error: error)
            }
        }
    }

    private nonisolated static func logPrefetchFailure(_ kind: String, account: UUID, error: any Error) {
        persistenceLogger.info(
            """
            Background \(kind, privacy: .public) warm failed for account \
            \(account.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)
            """
        )
    }
}
