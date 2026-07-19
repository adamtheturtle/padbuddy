//
//  SerialWriteQueue.swift
//  BuddyAppKit
//

import Foundation
import os

/// Serializes detached persistence writes in submission order. Without this, two
/// `Task.detached` writes issued in quick succession can finish out of order and
/// leave a stale snapshot (or an orphaned file) on disk.
public final class SerialWriteQueue: Sendable {
    private struct Job {
        let priority: TaskPriority
        let work: @Sendable () -> Void
    }

    private struct State {
        var jobs: [Job] = []
        var nextIndex = 0
        var isRunning = false
        var idleWaiters: [CheckedContinuation<Void, Never>] = []
    }

    private let state = OSAllocatedUnfairLock<State>(initialState: State())

    public init() {}

    @preconcurrency public func enqueue(
        priority: TaskPriority = .utility,
        _ work: @Sendable @escaping () -> Void
    ) {
        let shouldStart = state.withLock { state in
            state.jobs.append(Job(priority: priority, work: work))
            guard !state.isRunning else { return false }

            state.isRunning = true
            return true
        }
        if shouldStart {
            Task.detached(priority: priority) { await self.run() }
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

    private func run() async {
        while let job = nextJob() {
            await Task.detached(priority: job.priority) {
                job.work()
            }.value
        }
    }

    private func nextJob() -> Job? {
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
            return (job, [])
        }
        result.1.forEach { $0.resume() }
        return result.0
    }
}
