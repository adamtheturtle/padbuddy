//
//  ScreenReportOperationLimiter.swift
//  coderpad
//

import Foundation

private typealias ScreenReportWaitContinuation = CheckedContinuation<Void, any Error>

/// A process-wide gate for sensitive, potentially large Screen report downloads.
/// It is shared by every `ScreenClient`, so opening reports in several windows or
/// accounts cannot create an unbounded collection of in-flight temporary files.
actor ScreenReportOperationLimiter {
    static let shared = ScreenReportOperationLimiter(maximumConcurrentOperations: 2)

    private let maximumConcurrentOperations: Int
    private var activeOperations = 0
    private var waiterOrder: [UUID] = []
    private var waiters: [UUID: ScreenReportWaitContinuation] = [:]
    /// Operations that have started but not yet finished, so a cancellation for an
    /// unknown id is ignored rather than recorded forever.
    private var liveOperations: Set<UUID> = []
    /// Cancellations that arrived before the operation reached the wait queue. Without
    /// this the cancel found no waiter, was dropped, and the operation then queued and
    /// waited for a permit nobody was going to reclaim (#4557).
    private var cancelledBeforeQueueing: Set<UUID> = []

    init(maximumConcurrentOperations: Int) {
        precondition(maximumConcurrentOperations > 0)
        self.maximumConcurrentOperations = maximumConcurrentOperations
    }

    var hasQueuedWaiters: Bool {
        !waiterOrder.isEmpty
    }

    func acquire(id: UUID) async throws {
        try Task.checkCancellation()
        if activeOperations < maximumConcurrentOperations {
            activeOperations += 1
            return
        }

        try await withCheckedThrowingContinuation { (continuation: ScreenReportWaitContinuation) in
            if Task.isCancelled || cancelledBeforeQueueing.contains(id) {
                continuation.resume(throwing: CancellationError())
            } else {
                waiterOrder.append(id)
                waiters[id] = continuation
            }
        }

        // Resumed by `release()`, which handed this waiter its permit. A cancellation
        // that lost the race to that handover would otherwise go unnoticed here and the
        // download the user cancelled would start anyway, so the permit is passed on
        // instead of being used (#4557).
        if Task.isCancelled {
            release()
            throw CancellationError()
        }
    }

    /// Runs one report operation while holding a process-wide permit.
    func perform<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        let id = UUID()
        liveOperations.insert(id)
        defer { finish(id: id) }

        return try await withTaskCancellationHandler {
            try await acquire(id: id)
            defer { release() }
            return try await operation()
        } onCancel: {
            Task { await self.cancel(id: id) }
        }
    }

    func cancel(id: UUID) {
        if let index = waiterOrder.firstIndex(of: id) {
            waiterOrder.remove(at: index)
            waiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
            return
        }

        // The waiter is not queued yet. Remember the cancellation only while the
        // operation is live, so this set cannot accumulate ids that never queue.
        guard liveOperations.contains(id) else { return }

        cancelledBeforeQueueing.insert(id)
    }

    func release() {
        guard waiterOrder.isEmpty else {
            let id = waiterOrder.removeFirst()
            waiters.removeValue(forKey: id)?.resume()
            return
        }

        precondition(activeOperations > 0)
        activeOperations -= 1
    }

    private func finish(id: UUID) {
        liveOperations.remove(id)
        cancelledBeforeQueueing.remove(id)
    }
}
