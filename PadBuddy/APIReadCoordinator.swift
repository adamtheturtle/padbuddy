//
//  APIReadCoordinator.swift
//  coderpad
//

import Foundation

actor FreshRequestCoalescer<Key: Hashable & Sendable, Value: Sendable> {
    private struct Fresh {
        let value: Value
        let date: Date
    }

    private struct InFlight {
        let generation: UInt64
        let isForced: Bool
        let task: Task<Value, any Error>
    }

    private let freshness: TimeInterval
    private var nextGeneration: UInt64 = 0
    private var generations = FreshRequestGenerations<Key>()
    private var tasks: [Key: InFlight] = [:]
    private var values: [Key: Fresh] = [:]

    init(freshness: TimeInterval) {
        self.freshness = freshness
    }

    func value(
        for key: Key, force: Bool = false,
        fetch: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        if let inFlight = tasks[key], !force || inFlight.isForced {
            return try await cancellableValue(of: inFlight.task)
        }
        if !force, let cached = values[key], Date().timeIntervalSince(cached.date) < freshness {
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
            values[key] = Fresh(value: value, date: Date())
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
}
