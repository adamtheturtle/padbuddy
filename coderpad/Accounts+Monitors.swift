//
//  Accounts+Monitors.swift
//  coderpad
//
//  Observable monitors for account key health and pad activity.
//

import AsyncAlgorithms
import Foundation

/// Re-checks account keys on a timer so a key revoked mid-session surfaces the
/// unauthorized banner without needing a section switch. Each result remains tied to
/// the exact client identity that initiated it, so rekeying or removing an account while
/// its request is suspended cannot publish a stale verdict.
@MainActor
@Observable
final class AccountHealthMonitor {
    static let shared = AccountHealthMonitor()

    private var currentUnauthorized: Set<UUID> = []
    private(set) var lastChecked: Date?
    @ObservationIgnored private var currentLoop: Task<Void, Never>?
    /// Bad keys detected on NON-current accounts by the rotation sweep (#1777);
    /// the generic monitor only tracks the account its probe closure names.
    private var sweepUnauthorized: Set<UUID> = []
    /// The sweep task for non-current accounts; see ``start(every:)``.
    @ObservationIgnored private var sweepLoop: Task<Void, Never>?

    var unauthorizedAccountIDs: Set<UUID> {
        currentUnauthorized.union(sweepUnauthorized)
    }

    private init() {}

    /// Re-checks the current account's key on a fixed interval (default 30 min),
    /// and sweeps every other eligible account on the same cadence: revoked
    /// credentials on a non-current account (All Accounts mode, a pinned widget)
    /// must surface without a manual account switch (#1777). Idempotent: repeated
    /// calls keep the single existing timers.
    func start(every interval: Duration = .seconds(1800)) {
        if currentLoop == nil {
            let cadence = interval > .zero ? interval : .milliseconds(1)
            currentLoop = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.checkCurrentAccount()
                    do {
                        try await Task.sleep(for: cadence)
                    } catch {
                        break
                    }
                }
            }
        }
        guard sweepLoop == nil else { return }

        let interval = interval > .zero ? interval : .milliseconds(1)
        sweepLoop = Task { [weak self] in
            for await _ in AsyncTimerSequence.repeating(every: interval) {
                await self?.checkOtherAccounts()
            }
        }
    }

    // Deliberate monitor lifecycle API, kept for start/stop symmetry.
    // periphery:ignore
    func stop() {
        currentLoop?.cancel()
        currentLoop = nil
        sweepLoop?.cancel()
        sweepLoop = nil
    }

    func checkCurrentAccount() async {
        guard let account = AccountsStore.shared.currentAccount,
              account.isBadKeyDemo || (!account.isMock && !account.apiKey.isEmpty) else { return }

        let client = account.makeClient()
        do {
            _ = try await client.quota()
            guard AccountsStore.shared.isCurrentClient(client, for: account.id) else { return }

            currentUnauthorized.remove(account.id)
        } catch {
            guard AccountsStore.shared.isCurrentClient(client, for: account.id) else { return }

            if (error as? CoderPadError)?.isUnauthorized == true {
                currentUnauthorized.insert(account.id)
            }
        }
        let live = Set(AccountsStore.shared.accounts.map(\.id))
        currentUnauthorized.formIntersection(live)
        lastChecked = Date()
    }

    /// Probes every eligible non-current account's key (#1777). Sequential to keep
    /// the background load low, like the pads refresher's sweep.
    private func checkOtherAccounts() async {
        let currentID = AccountsStore.shared.currentAccount?.id
        for account in AccountsStore.shared.accounts where account.id != currentID {
            guard account.isBadKeyDemo || (!account.isMock && !account.apiKey.isEmpty) else { continue }

            let client = account.makeClient()
            do {
                _ = try await client.quota()
                guard AccountsStore.shared.isCurrentClient(client, for: account.id) else { continue }

                sweepUnauthorized.remove(account.id)
            } catch {
                guard AccountsStore.shared.isCurrentClient(client, for: account.id) else { continue }

                if (error as? CoderPadError)?.isUnauthorized == true {
                    sweepUnauthorized.insert(account.id)
                }
            }
        }
        // Verdicts for removed accounts must not linger.
        let live = Set(AccountsStore.shared.accounts.map(\.id))
        sweepUnauthorized.formIntersection(live)
    }

    func isUnauthorized(_ accountID: UUID) -> Bool {
        currentUnauthorized.contains(accountID) || sweepUnauthorized.contains(accountID)
    }

    /// Clear a stale unauthorized verdict, e.g. when the account's key is changed
    /// in place. A fresh `checkCurrentAccount` re-flags it if the new key is also
    /// revoked, but until then the banner shouldn't claim the new key is bad.
    func clearUnauthorized(_ accountID: UUID) {
        currentUnauthorized.remove(accountID)
        sweepUnauthorized.remove(accountID)
    }
}

/// Keeps the current account's pads fresh on a timer, independent of any UI.
///
/// Normal use already refreshes the cache: opening the menu bar, opening a window,
/// or switching sections all refetch. The one gap is an app left running with no
/// window open and the menu never clicked while pads change server-side — nothing
/// fetches in that state, so the Recent Pads widget and Dock badge show the last
/// snapshot until the next interaction. This closes that gap.
///
/// Writing the result through `PadsCacheStore.set` is what makes it worthwhile: that
/// cascades to the widget's shared snapshot and the active-pads Dock badge, so both
/// stay current without any window on screen.
@MainActor
final class PadsBackgroundRefresher {
    nonisolated struct FetchJob {
        let accountID: UUID
        let apiKey: String
        let baseURL: URL
    }

    nonisolated struct FetchResult {
        let accountID: UUID
        let clientIdentity: ClientTaskIdentity
        let pads: [Pad]
    }

    nonisolated enum FailureKind: String {
        case timeout
        case unauthorized
        case network
        case server
        case invalidResponse
        case other
    }

    nonisolated enum FetchOutcome {
        case success(FetchResult)
        case failure(accountID: UUID, clientIdentity: ClientTaskIdentity, kind: FailureKind)
        case cancelled
    }

    struct FailureState: Equatable {
        let clientIdentity: ClientTaskIdentity
        let kind: FailureKind
        let consecutiveFailures: Int
        let lastFailure: Date
        let retryAfter: Date
    }

    struct AccountActivityState {
        let clientIdentity: ClientTaskIdentity
        let snapshot: [String: PadActivitySnapshot]
    }

    static let shared = PadsBackgroundRefresher()
    private var loop: Task<Void, Never>?
    /// Main-actor reentrancy allows a manual call or late timer tick to enter while
    /// an earlier sweep is awaiting the network. Only one sweep may own snapshots.
    private var refreshInFlight = false
    /// Per-account activity snapshots from the previous sweep, so the windowless
    /// refresher can diff and post pad-update notifications like the pad list
    /// does (#735). An account's first sweep only seeds its snapshot, so a cold
    /// start never alerts about every existing pad.
    private var previousActivity: [UUID: AccountActivityState] = [:]
    var failuresByAccount: [UUID: FailureState] = [:]
    static let maximumConcurrentFetches = 3
    static let perAccountTimeout: Duration = .seconds(45)
    private init() {}

    /// Refetches the current account's pads on a fixed interval (default 5 min).
    /// Idempotent: repeated calls keep the single existing timer. Started once at
    /// launch so it runs whether or not a window is open — unlike the per-section
    /// loads, which only fire while the UI is on screen.
    func start(every interval: Duration = .seconds(300)) {
        guard loop == nil else { return }

        // No immediate fetch (`runImmediately: false`): launch already presents a window
        // that loads the current account, so the first useful background tick is one
        // interval out.
        let interval = interval > .zero ? interval : .milliseconds(1)
        let loop = Task { [weak self] in
            for await _ in AsyncTimerSequence.repeating(every: interval) {
                await self?.refreshAllAccounts()
            }
        }
        self.loop = loop
    }

    // Deliberate monitor lifecycle API, kept for start/stop symmetry.
    // periphery:ignore
    func stop() {
        loop?.cancel()
        loop = nil
    }

    /// Refetches pads for every account a persistent consumer can need (#736): the
    /// all-accounts badge scope counts every account's cache and a widget can pin any
    /// account, so the sweep isn't limited to the current account - which is even
    /// absent in All Accounts mode, where the old current-only refresh did nothing.
    func refreshAllAccounts() async {
        guard !refreshInFlight else { return }

        refreshInFlight = true
        defer { refreshInFlight = false }

        // Snapshots for accounts that no longer exist must not accumulate for the
        // process lifetime (#1778).
        let live = Set(AccountsStore.shared.accounts.map(\.id))
        previousActivity = previousActivity.filter { live.contains($0.key) }
        failuresByAccount = failuresByAccount.filter { live.contains($0.key) }

        // One alert per account: the notifier coalesces onto per-account
        // identifiers (#1144, refining #1038 - the old single identifier meant
        // per-account calls cancelled each other, which forced a merged,
        // unattributed alert), so each organization's activity is named and
        // stands on its own.
        let now = Date()
        let jobs = AccountsStore.shared.accounts.compactMap { account -> FetchJob? in
            guard !account.isMock else { return nil }

            let apiKey = account.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !apiKey.isEmpty else { return nil }

            let job = FetchJob(accountID: account.id, apiKey: apiKey, baseURL: account.resolvedBaseURL)
            let identity = ClientTaskIdentity(apiKey: apiKey, baseURL: job.baseURL)
            if let failure = failuresByAccount[account.id],
               failure.clientIdentity == identity, failure.retryAfter > now { return nil }
            return job
        }

        await withTaskGroup(of: FetchOutcome.self) { group in
            var pending = jobs.makeIterator()
            for _ in 0 ..< min(Self.maximumConcurrentFetches, jobs.count) {
                if let job = pending.next() { Self.addFetch(job, to: &group) }
            }

            while let outcome = await group.next() {
                apply(outcome)
                if let job = pending.next() { Self.addFetch(job, to: &group) }
            }
        }
    }

    private nonisolated static func addFetch(
        _ job: FetchJob,
        to group: inout TaskGroup<FetchOutcome>
    ) {
        group.addTask {
            await fetch(job, timeout: perAccountTimeout)
        }
    }

    private nonisolated static func fetch(_ job: FetchJob, timeout: Duration) async -> FetchOutcome {
        let identity = ClientTaskIdentity(apiKey: job.apiKey, baseURL: job.baseURL)
        return await withTaskGroup(of: FetchOutcome.self) { group in
            group.addTask {
                let client = CoderPadClient.live(apiKey: job.apiKey, baseURL: job.baseURL)
                do {
                    let pads = try await client.listPads(sort: "updated_at,desc")
                    return .success(FetchResult(
                        accountID: job.accountID, clientIdentity: identity, pads: pads
                    ))
                } catch is CancellationError {
                    return .cancelled
                } catch {
                    return .failure(
                        accountID: job.accountID,
                        clientIdentity: identity,
                        kind: failureKind(for: error)
                    )
                }
            }
            group.addTask {
                do {
                    try await Task.sleep(for: timeout)
                    return .failure(
                        accountID: job.accountID,
                        clientIdentity: identity,
                        kind: .timeout
                    )
                } catch {
                    return .cancelled
                }
            }

            let first = await group.next()
            group.cancelAll()
            guard let first else { return .cancelled }

            return first
        }
    }

    private func apply(_ outcome: FetchOutcome) {
        switch outcome {
        case let .success(result):
            apply(result)
        case let .failure(accountID, identity, kind):
            recordFailure(accountID: accountID, clientIdentity: identity, kind: kind)
        case .cancelled:
            break
        }
    }

    private func apply(_ result: FetchResult) {
        guard let account = AccountsStore.shared.accounts.first(where: { $0.id == result.accountID }) else { return }

        let client = account.makeClient()
        guard client.taskIdentity == result.clientIdentity else { return }

        failuresByAccount[account.id] = nil
        let changes = ownedChanges(account: account, client: client, fetched: result.pads)
        let cached = PadsCacheStore.shared.get(account.id)
        if Self.cacheNeedsUpdate(cached: cached, fetched: result.pads) {
            PadsCacheStore.shared.set(account.id, pads: result.pads, via: client)
        }
        PadUpdateNotifier.shared.notify(changes: changes, account: account)
    }

    static func cacheNeedsUpdate(cached: [Pad], fetched: [Pad]) -> Bool {
        cached != fetched
    }

    /// The background-detected activity for one account, feeding the opt-in pad-update
    /// alerts so closing every window doesn't silently disable notifications (#735).
    /// Shares the pad list's diff/classification and its "only the user's own pads"
    /// narrowing (#424); PadUpdateNotifier itself still gates on the preference,
    /// permission, and the app being inactive.
    private func ownedChanges(account: Account, client: CoderPadClient, fetched: [Pad]) -> [PadChange] {
        let snapshot = PadsView.activitySnapshot(of: fetched)
        guard let previous = Self.replaceSnapshot(accountID: account.id,
                                                  clientIdentity: client.taskIdentity,
                                                  snapshot: snapshot,
                                                  states: &previousActivity) else { return [] }

        return PadsView.padChanges(in: fetched, since: previous).filter { account.owns($0.pad.ownerEmail) }
    }

    /// Returns a comparable prior snapshot only when it came from the same backend.
    /// A re-key/server change seeds a fresh baseline instead of diffing unrelated pads.
    static func replaceSnapshot(accountID: UUID,
                                clientIdentity: ClientTaskIdentity,
                                snapshot: [String: PadActivitySnapshot],
                                states: inout [UUID: AccountActivityState]) -> [String: PadActivitySnapshot]? {
        let previous = states[accountID]
        states[accountID] = AccountActivityState(clientIdentity: clientIdentity, snapshot: snapshot)
        guard previous?.clientIdentity == clientIdentity else { return nil }

        return previous?.snapshot
    }
}

@Observable
final class PadActivityMonitor {
    static let shared = PadActivityMonitor()
    var unseenChangedCount: Int = 0

    private init() {}

    func record(changedCount: Int) {
        // Zero clears too: a refresh that found no changes must not leave an
        // obsolete nonzero activity indicator standing forever (#1780).
        unseenChangedCount = changedCount
    }
}
