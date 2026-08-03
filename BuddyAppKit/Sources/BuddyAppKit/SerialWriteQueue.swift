//
//  SerialWriteQueue.swift
//  BuddyAppKit
//

import Dispatch
import Foundation
import os

public enum SerialWriteQueueError: Error, Equatable {
    case coalesced
    case dropped
}

/// Serializes detached persistence writes in submission order. Without this, two
/// `Task.detached` writes issued in quick succession can finish out of order and
/// leave a stale snapshot (or an orphaned file) on disk.
public final class SerialWriteQueue: Sendable {
    private struct Job {
        let coalescingKey: String?
        let work: @Sendable () -> Void
        let onDiscard: @Sendable (SerialWriteQueueError) -> Void
    }

    private struct State {
        var jobs: [Job] = []
        var nextIndex = 0
        var isRunning = false
        var idleWaiters: [CheckedContinuation<Void, Never>] = []
        var coalescedCount = 0
        var droppedCount = 0
    }

    private let state = OSAllocatedUnfairLock<State>(initialState: State())
    private let worker = DispatchQueue(label: "BuddyAppKit.SerialWriteQueue", qos: .utility)
    public let maximumPendingJobs: Int

    public init(maximumPendingJobs: Int = 256) {
        self.maximumPendingJobs = max(1, maximumPendingJobs)
    }

    public struct Metrics: Sendable, Equatable {
        public let pendingCount: Int
        public let coalescedCount: Int
        public let droppedCount: Int
    }

    public var metrics: Metrics {
        state.withLock {
            Metrics(pendingCount: max(0, $0.jobs.count - $0.nextIndex),
                    coalescedCount: $0.coalescedCount,
                    droppedCount: $0.droppedCount)
        }
    }

    @preconcurrency public func enqueue(
        priority: TaskPriority = .utility,
        coalescingKey: String? = nil,
        _ work: @Sendable @escaping () -> Void
    ) {
        // Retain the argument for source compatibility. Every write runs on the
        // queue's fixed-priority worker so a later urgent caller cannot allocate a
        // high-priority task that waits behind earlier persistence work (#1275).
        _ = priority
        submit(Job(coalescingKey: coalescingKey, work: work, onDiscard: { _ in }))
    }

    /// Enqueues async persistence work and suspends until it executes, surfacing both
    /// work failures and admission loss caused by coalescing/backpressure.
    @preconcurrency public func enqueueAndWait(
        priority: TaskPriority = .utility,
        coalescingKey: String? = nil,
        _ work: @Sendable @escaping () async throws -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let job = Job(
                coalescingKey: coalescingKey,
                work: {
                    let finished = DispatchSemaphore(value: 0)
                    Task.detached(priority: priority) {
                        do {
                            try await work()
                            continuation.resume()
                        } catch {
                            continuation.resume(throwing: error)
                        }
                        finished.signal()
                    }
                    finished.wait()
                },
                onDiscard: { continuation.resume(throwing: $0) }
            )
            submit(job)
        }
    }

    private func submit(_ job: Job) {
        let admission = state.withLock { state -> (shouldStart: Bool, discarded: (Job, SerialWriteQueueError)?) in
            if let coalescingKey = job.coalescingKey,
               let index = state.jobs[state.nextIndex...].lastIndex(where: { $0.coalescingKey == coalescingKey }) {
                let discarded = state.jobs[index]
                state.jobs[index] = job
                state.coalescedCount += 1
                return (false, (discarded, .coalesced))
            }
            var discarded: (Job, SerialWriteQueueError)?
            if state.jobs.count - state.nextIndex >= maximumPendingJobs {
                discarded = (state.jobs.remove(at: state.nextIndex), .dropped)
                state.droppedCount += 1
            }
            state.jobs.append(job)
            guard !state.isRunning else { return (false, discarded) }

            state.isRunning = true
            return (true, discarded)
        }
        if let (job, error) = admission.discarded {
            job.onDiscard(error)
        }
        if admission.shouldStart {
            worker.async { self.run() }
        }
    }

    public func waitUntilIdle() async {
        await withCheckedContinuation { continuation in
            let isIdle = state.withLock { state in
                guard state.isRunning else { return true }

                state.idleWaiters.append(continuation)
                return false
            }
            if isIdle {
                continuation.resume()
            }
        }
    }

    private nonisolated func run() {
        while let job = nextJob() {
            job.work()
        }
    }

    private nonisolated func nextJob() -> Job? {
        let result: (Job?, [CheckedContinuation<Void, Never>]) = state.withLock { state in
            guard state.nextIndex < state.jobs.count else {
                state.jobs.removeAll(keepingCapacity: true)
                state.nextIndex = 0
                state.isRunning = false
                let waiters = state.idleWaiters
                state.idleWaiters = []
                return (nil, waiters)
            }

            let job = state.jobs[state.nextIndex]
            state.nextIndex += 1
            if state.nextIndex >= 64, state.nextIndex * 2 >= state.jobs.count {
                state.jobs.removeFirst(state.nextIndex)
                state.nextIndex = 0
            }
            return (job, [])
        }
        result.1.forEach { $0.resume() }
        return result.0
    }
}
