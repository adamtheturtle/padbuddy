//
//  SerialWriteQueue.swift
//  BuddyAppKit
//

import Dispatch
import Foundation
import os

/// Serializes detached persistence writes in submission order. Without this, two
/// `Task.detached` writes issued in quick succession can finish out of order and
/// leave a stale snapshot (or an orphaned file) on disk.
public final class SerialWriteQueue: Sendable {
    private struct Job {
        let coalescingKey: String?
        let work: @Sendable () -> Void
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
        let shouldStart = state.withLock { state in
            let job = Job(coalescingKey: coalescingKey, work: work)
            if let coalescingKey,
               let index = state.jobs[state.nextIndex...].lastIndex(where: { $0.coalescingKey == coalescingKey }) {
                state.jobs[index] = job
                state.coalescedCount += 1
                return false
            }
            if state.jobs.count - state.nextIndex >= maximumPendingJobs {
                state.jobs.remove(at: state.nextIndex)
                state.droppedCount += 1
            }
            state.jobs.append(job)
            guard !state.isRunning else { return false }

            state.isRunning = true
            return true
        }
        if shouldStart {
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
            if isIdle { continuation.resume() }
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
