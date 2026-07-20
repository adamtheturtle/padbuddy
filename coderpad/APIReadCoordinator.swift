//
//  APIReadCoordinator.swift
//  coderpad
//

import Foundation

actor FreshRequestCoalescer<Key: Hashable & Sendable, Value: Sendable> {
    private struct Fresh: Sendable {
        let value: Value
        let date: Date
    }

    private let freshness: TimeInterval
    private var tasks: [Key: Task<Value, any Error>] = [:]
    private var values: [Key: Fresh] = [:]

    init(freshness: TimeInterval) {
        self.freshness = freshness
    }

    func value(
        for key: Key, force: Bool = false,
        fetch: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        if let task = tasks[key] { return try await task.value }
        if !force, let cached = values[key], Date().timeIntervalSince(cached.date) < freshness {
            return cached.value
        }

        let task = Task { try await fetch() }
        tasks[key] = task
        do {
            let value = try await task.value
            tasks[key] = nil
            values[key] = Fresh(value: value, date: Date())
            return value
        } catch {
            tasks[key] = nil
            throw error
        }
    }

    func invalidate(where predicate: (Key) -> Bool) {
        values = values.filter { !predicate($0.key) }
    }
}

/// Process-wide coalescing and freshness for the expensive complete-list reads.
actor APIReadCoordinator {
    static let shared = APIReadCoordinator()

    struct Key: Hashable, Sendable {
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

    func invalidate(accountID: UUID) async {
        await padReads.invalidate { $0.accountID == accountID }
        await questionReads.invalidate { $0.accountID == accountID }
    }
}
