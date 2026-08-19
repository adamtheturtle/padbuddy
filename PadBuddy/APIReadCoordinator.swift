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
        let isForced: Bool
        let task: Task<Value, any Error>
    }

    private var nextGeneration: UInt64 = 0
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
        if let inFlight = tasks[key], !force || inFlight.isForced {
            return try await cancellableValue(of: inFlight.task)
        }
        if !force, let cached = values[key], cached.instant.duration(to: now()) < freshness {
            nextAccess &+= 1
            values[key] = Fresh(value: cached.value, instant: cached.instant, lastAccess: nextAccess)
            return cached.value
        }

        let task = Task { try await fetch() }
        nextGeneration &+= 1
        let generation = nextGeneration
        generations.begin(generation, for: key)
        tasks[key] = InFlight(generation: generation, isForced: force, task: task)
        Task { [weak self] in
            let result = await task.result
            await self?.finish(result, for: key, generation: generation)
        }
        return try await cancellableValue(of: task)
    }

    private func finish(
        _ result: Result<Value, any Error>, for key: Key, generation: UInt64
    ) {
        guard clearTaskIfCurrent(for: key, generation: generation) else { return }

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
            tasks.removeValue(forKey: key)?.task.cancel()
            generations.remove(for: key)
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
}
