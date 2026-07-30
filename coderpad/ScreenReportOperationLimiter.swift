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
    private var waiters: [(id: UUID, continuation: ScreenReportWaitContinuation)] = []

    init(maximumConcurrentOperations: Int) {
        precondition(maximumConcurrentOperations > 0)
        self.maximumConcurrentOperations = maximumConcurrentOperations
    }

    func acquire(id: UUID) async throws {
        try Task.checkCancellation()
        if activeOperations < maximumConcurrentOperations {
            activeOperations += 1
            return
        }

        try await withCheckedThrowingContinuation { (continuation: ScreenReportWaitContinuation) in
            if Task.isCancelled {
                continuation.resume(throwing: CancellationError())
            } else {
                waiters.append((id, continuation))
            }
        }
    }

    /// Runs one report operation while holding a process-wide permit.
    func perform<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await acquire(id: id)
            defer { release() }
            return try await operation()
        } onCancel: {
            Task { await self.cancel(id: id) }
        }
    }

    func cancel(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }

        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }

    func release() {
        while !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            waiter.continuation.resume()
            return
        }
        precondition(activeOperations > 0)
        activeOperations -= 1
    }
}
