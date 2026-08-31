//
//  APIReadCoordinator.swift
//  coderpad
//

import Foundation

actor FreshRequestCoalescer<Key: Hashable & Sendable, Value: Sendable> {
    private struct Fresh {
        let value: Value
        let instant: ContinuousClock.Instant
        let lastAccess: UInt64
    }

    private let freshness: Duration
    private let maximumCachedValues: Int
    private let now: @Sendable () -> ContinuousClock.Instant
    private struct InFlight {
        let generation: UInt64
        let invalidationRevision: UInt64
        let isForced: Bool
        let task: Task<Value, any Error>
    }

    private var nextGeneration: UInt64 = 0
    /// Per-key mutation fences. Every waiter captures the revision of the fetch
    /// it joined, so invalidation can reject its eventual value even if another
    /// waiter already completed the shared task's bookkeeping (#5129).
    private var invalidationRevisions: [Key: UInt64] = [:]
    private var nextAccess: UInt64 = 0
    private var generations = FreshRequestGenerations<Key>()
    private var tasks: [Key: InFlight] = [:]
    private var values: [Key: Fresh] = [:]

    init(
        freshness: TimeInterval, maximumCachedValues: Int = 32,
        now: @escaping @Sendable () -> ContinuousClock.Instant = { .now }
    ) {
        self.freshness = .seconds(freshness)
        self.maximumCachedValues = max(0, maximumCachedValues)
        self.now = now
    }

    func value(
        for key: Key, force: Bool = false,
        fetch: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        if let inFlight = tasks[key],
           invalidationRevisions[key, default: 0] == inFlight.invalidationRevision,
           !force || inFlight.isForced {
            let value = try await cancellableValue(of: inFlight.task)
            try rejectIfInvalidated(key, revision: inFlight.invalidationRevision)
            finish(
                .success(value), for: key, generation: inFlight.generation,
                invalidationRevision: inFlight.invalidationRevision
            )
            return value
        }
        if !force, let cached = values[key], cached.instant.duration(to: now()) < freshness {
            nextAccess &+= 1
            values[key] = Fresh(value: cached.value, instant: cached.instant, lastAccess: nextAccess)
            return cached.value
        }

        // Detached, so the fetch and — the part that matters — its `JSONDecoder` work do
        // not run on this actor. Created inside an actor-isolated method, a plain `Task`
        // inherits the coalescer's executor, and the decode is synchronous CPU work over a
        // complete organization list: while it ran, every other account's `value(for:)`,
        // every `invalidateCached` from a mutation broadcast, and every account teardown
        // queued behind it. In merged mode the decodes serialized end to end even though
        // the fetches overlapped — the opposite of what this coalescer is for (#4765).
        // Only the bookkeeping below stays isolated.
        let task = Task.detached { try await fetch() }
        nextGeneration &+= 1
        let generation = nextGeneration
        let invalidationRevision = invalidationRevisions[key, default: 0]
        generations.begin(generation, for: key)
        tasks[key] = InFlight(
            generation: generation,
            invalidationRevision: invalidationRevision,
            isForced: force,
            task: task
        )
        Task { [weak self] in
            let result = await task.result
            await self?.finish(
                result, for: key, generation: generation,
                invalidationRevision: invalidationRevision
            )
        }
        let value = try await cancellableValue(of: task)
        try rejectIfInvalidated(key, revision: invalidationRevision)
        finish(
            .success(value), for: key, generation: generation,
            invalidationRevision: invalidationRevision
        )
        return value
    }

    private func finish(
        _ result: Result<Value, any Error>, for key: Key, generation: UInt64,
        invalidationRevision: UInt64
    ) {
        guard clearTaskIfCurrent(for: key, generation: generation) else { return }
        guard invalidationRevisions[key, default: 0] == invalidationRevision else { return }

        if case let .success(value) = result {
            nextAccess &+= 1
            values[key] = Fresh(value: value, instant: now(), lastAccess: nextAccess)
            evictCachedValuesIfNeeded()
        }
    }

    func remove(where shouldRemove: @Sendable (Key) -> Bool) {
        let cachedKeys = values.keys.filter(shouldRemove)
        for key in cachedKeys {
            values[key] = nil
        }
        let inFlightKeys = tasks.keys.filter(shouldRemove)
        for key in inFlightKeys {
            invalidationRevisions[key, default: 0] &+= 1
            tasks.removeValue(forKey: key)?.task.cancel()
            generations.remove(for: key)
        }
    }

    /// Drops cached values for matching keys and fences fetches already in
    /// flight. Their underlying shared work is allowed to finish, but every
    /// waiter receives cancellation rather than publishing a pre-mutation row
    /// set into a mounted view (#5129).
    func invalidateCached(where shouldRemove: @Sendable (Key) -> Bool) {
        let matchingKeys = Set(values.keys.filter(shouldRemove) + tasks.keys.filter(shouldRemove))
        for key in matchingKeys {
            values[key] = nil
            invalidationRevisions[key, default: 0] &+= 1
        }
    }

    private func rejectIfInvalidated(_ key: Key, revision: UInt64) throws {
        guard invalidationRevisions[key, default: 0] == revision else {
            throw CancellationError()
        }
    }

    private func evictCachedValuesIfNeeded() {
        while values.count > maximumCachedValues,
              let oldest = values.min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key {
            values[oldest] = nil
        }
    }

    private func clearTaskIfCurrent(for key: Key, generation: UInt64) -> Bool {
        guard tasks[key]?.generation == generation,
              generations.complete(generation, for: key) else { return false }

        tasks[key] = nil
        return true
    }
}

nonisolated struct FreshRequestGenerations<Key: Hashable> {
    private(set) var active: [Key: UInt64] = [:]

    mutating func begin(_ generation: UInt64, for key: Key) {
        active[key] = generation
    }

    mutating func complete(_ generation: UInt64, for key: Key) -> Bool {
        guard active[key] == generation else { return false }

        active[key] = nil
        return true
    }

    mutating func remove(for key: Key) {
        active[key] = nil
    }
}

/// Process-wide coalescing and freshness for the expensive complete-list reads.
actor APIReadCoordinator {
    static let shared = APIReadCoordinator()

    struct Key: Hashable {
        let accountID: UUID
        let baseURL: URL
        let apiKey: String
    }

    private let padReads: FreshRequestCoalescer<Key, [Pad]>
    private let questionReads: FreshRequestCoalescer<Key, [Question]>

    init(freshness: TimeInterval = 60) {
        padReads = FreshRequestCoalescer(freshness: freshness)
        questionReads = FreshRequestCoalescer(freshness: freshness)
    }

    func pads(accountID: UUID, client: CoderPadClient, force: Bool = false) async throws -> [Pad] {
        let key = Key(accountID: accountID, baseURL: client.baseURL, apiKey: client.apiKey)
        return try await padReads.value(for: key, force: force) {
            try await client.listPads(sort: "updated_at,desc")
        }
    }

    func questions(accountID: UUID, client: CoderPadClient, force: Bool = false) async throws -> [Question] {
        let key = Key(accountID: accountID, baseURL: client.baseURL, apiKey: client.apiKey)
        return try await questionReads.value(for: key, force: force) {
            try await client.listQuestions(sort: "updated_at,desc")
        }
    }

    func remove(accountID: UUID) async {
        await padReads.remove { $0.accountID == accountID }
        await questionReads.remove { $0.accountID == accountID }
    }

    func remove(baseURL: URL, apiKey: String) async {
        await padReads.remove { $0.baseURL == baseURL && $0.apiKey == apiKey }
        await questionReads.remove { $0.baseURL == baseURL && $0.apiKey == apiKey }
    }

    func invalidatePads(accountID: UUID) async {
        await padReads.invalidateCached { $0.accountID == accountID }
    }

    func invalidateQuestions(accountID: UUID) async {
        await questionReads.invalidateCached { $0.accountID == accountID }
    }
}
