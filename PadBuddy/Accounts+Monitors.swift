//
//  Accounts+Monitors.swift
//  coderpad
//

// swiftlint:disable file_length
import AsyncAlgorithms
import Foundation

@MainActor
@Observable
final class AccountHealthMonitor {
    static let shared = AccountHealthMonitor()

    /// What the last completed check said about an account.
    ///
    /// One verdict per account, not one per monitor loop. The current-account loop and the
    /// sweep used to keep separate sets and expose their union, so a success in one loop
    /// cleared only its own set: an account that a sweep had marked unauthorized stayed
    /// unauthorized however many times the current-account check succeeded, until the
    /// sweep happened to run again (#4687).
    enum Verdict: Equatable {
        case unauthorized
        case unavailable
    }

    private var verdicts: [UUID: Verdict] = [:]
    private(set) var lastChecked: Date?
    private var lastSuccessfulByAccount: [UUID: Date] = [:]
    @ObservationIgnored private var currentLoop: Task<Void, Never>?
    @ObservationIgnored private var sweepLoop: Task<Void, Never>?

    var unauthorizedAccountIDs: Set<UUID> {
        Set(verdicts.filter { $0.value == .unauthorized }.keys)
    }

    private init() {}

    /// Re-checks current and other eligible accounts on a fixed interval (#1777).
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

            record(nil, for: account.id)
            lastSuccessfulByAccount[account.id] = Date()
        } catch {
            guard AccountsStore.shared.isCurrentClient(client, for: account.id) else { return }

            record((error as? CoderPadError)?.isUnauthorized == true ? .unauthorized : .unavailable,
                   for: account.id)
        }
        pruneRemovedAccounts()
        lastChecked = Date()
    }

    /// Probes every eligible non-current account's key sequentially (#1777).
    private func checkOtherAccounts() async {
        let currentID = AccountsStore.shared.currentAccount?.id
        for account in AccountsStore.shared.accounts where account.id != currentID {
            guard account.isBadKeyDemo || (!account.isMock && !account.apiKey.isEmpty) else { continue }

            let client = account.makeClient()
            do {
                _ = try await client.quota()
                guard AccountsStore.shared.isCurrentClient(client, for: account.id) else { continue }

                record(nil, for: account.id)
                lastSuccessfulByAccount[account.id] = Date()
            } catch {
                guard AccountsStore.shared.isCurrentClient(client, for: account.id) else { continue }

                record((error as? CoderPadError)?.isUnauthorized == true ? .unauthorized : .unavailable,
                       for: account.id)
            }
        }
        pruneRemovedAccounts()
    }

    /// Publishes the newest verdict for an account, whichever loop produced it. `nil`
    /// means the check succeeded and the account is healthy.
    private func record(_ verdict: Verdict?, for accountID: UUID) {
        verdicts[accountID] = verdict
    }

    /// Verdicts for removed accounts must not linger.
    private func pruneRemovedAccounts() {
        let live = Set(AccountsStore.shared.accounts.map(\.id))
        verdicts = verdicts.filter { live.contains($0.key) }
        lastSuccessfulByAccount = lastSuccessfulByAccount.filter { live.contains($0.key) }
    }

    func isUnauthorized(_ accountID: UUID) -> Bool {
        verdicts[accountID] == .unauthorized
    }

    func isUnavailable(_ accountID: UUID) -> Bool {
        verdicts[accountID] == .unavailable
    }

    func lastSuccessfulCheck(for accountID: UUID) -> Date? {
        lastSuccessfulByAccount[accountID]
    }

    func clearUnauthorized(_ accountID: UUID) {
        verdicts[accountID] = nil
        lastSuccessfulByAccount[accountID] = nil
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
@Observable
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
        let jobs = Self.prioritize(AccountsStore.shared.accounts.compactMap { account -> FetchJob? in
            guard !account.isMock else { return nil }

            let apiKey = account.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !apiKey.isEmpty else { return nil }

            let job = FetchJob(accountID: account.id, apiKey: apiKey, baseURL: account.resolvedBaseURL)
            let identity = ClientTaskIdentity(apiKey: apiKey, baseURL: job.baseURL)
            if let failure = failuresByAccount[account.id],
               failure.clientIdentity == identity, failure.retryAfter > now {
                return nil
            }
            return job
        })
        let cacheLoads = Self.beginCacheLoads(for: jobs)

        await withTaskGroup(of: FetchOutcome.self) { group in
            var pending = jobs.makeIterator()
            for _ in 0 ..< min(Self.maximumConcurrentFetches, jobs.count) {
                if let job = pending.next() {
                    Self.addFetch(job, to: &group)
                }
            }

            while let outcome = await group.next() {
                apply(outcome, cacheLoads: cacheLoads)
                if let job = pending.next() {
                    Self.addFetch(job, to: &group)
                }
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

    /// Races the fetch against its deadline without waiting for the loser.
    ///
    /// This used to be a `withTaskGroup`, and leaving a task group waits for every child:
    /// cancelling the API call did not end the wait if the transport ignored or delayed
    /// cancellation, so the nominal timeout bounded nothing (#4688). The losing task is
    /// abandoned instead — it finishes on its own and its result is discarded.
    private nonisolated static func fetch(_ job: FetchJob, timeout: Duration) async -> FetchOutcome {
        let identity = ClientTaskIdentity(apiKey: job.apiKey, baseURL: job.baseURL)
        let race = SingleResume<FetchOutcome>()

        let work = Task {
            await race.finish(performFetch(job, identity: identity))
        }
        let timer = Task {
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return
            }
            work.cancel()
            race.finish(.failure(accountID: job.accountID, clientIdentity: identity, kind: .timeout))
        }
        defer { timer.cancel() }

        return await withTaskCancellationHandler {
            await withCheckedContinuation { race.attach($0) }
        } onCancel: {
            work.cancel()
            timer.cancel()
            race.finish(.cancelled)
        }
    }

    private nonisolated static func performFetch(
        _ job: FetchJob, identity: ClientTaskIdentity
    ) async -> FetchOutcome {
        let client = await CoderPadClient.live(apiKey: job.apiKey, baseURL: job.baseURL)
        do {
            let pads = try await APIReadCoordinator.shared.pads(accountID: job.accountID, client: client)
            return .success(FetchResult(accountID: job.accountID, clientIdentity: identity, pads: pads))
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

    private func apply(_ outcome: FetchOutcome, cacheLoads: [UUID: Int]) {
        switch outcome {
        case let .success(result):
            guard let cacheLoad = cacheLoads[result.accountID] else { return }

            apply(result, cacheLoad: cacheLoad)

        case let .failure(accountID, identity, kind):
            recordFailure(accountID: accountID, clientIdentity: identity, kind: kind)

        case .cancelled:
            break
        }
    }

    private func apply(_ result: FetchResult, cacheLoad: Int) {
        guard let account = AccountsStore.shared.accounts.first(where: { $0.id == result.accountID }) else { return }

        let client = account.makeClient()
        guard client.taskIdentity == result.clientIdentity else { return }

        failuresByAccount[account.id] = nil
        let changes = ownedChanges(account: account, client: client, fetched: result.pads)
        let cached = PadsCacheStore.shared.get(account.id)
        if Self.cacheNeedsUpdate(cached: cached, fetched: result.pads) {
            PadsCacheStore.shared.set(account.id, pads: result.pads, via: client, accepting: cacheLoad)
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
