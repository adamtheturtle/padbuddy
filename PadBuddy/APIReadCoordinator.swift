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
        let generation: UUID
        let isForced: Bool
        let task: Task<Result<Value, any Error>, Never>
    }

    private let freshness: TimeInterval
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
            return try await inFlight.task.value.get()
        }
        if !force, let cached = values[key], Date().timeIntervalSince(cached.date) < freshness {
            return cached.value
        }

        let inFlight = InFlight(
            generation: UUID(),
            isForced: force,
            task: Task {
                do {
                    return try await .success(fetch())
                } catch {
                    return .failure(error)
                }
            }
        )
        tasks[key] = inFlight
        do {
            let value = try await inFlight.task.value.get()
            if tasks[key]?.generation == inFlight.generation {
                tasks[key] = nil
                values[key] = Fresh(value: value, date: Date())
            }
            return value
        } catch {
            if tasks[key]?.generation == inFlight.generation {
                tasks[key] = nil
            }
            throw error
        }
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
