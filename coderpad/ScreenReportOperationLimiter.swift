//
//  ScreenReportOperationLimiter.swift
//  coderpad
//

import Foundation

/// A process-wide gate for sensitive, potentially large Screen report downloads.
/// It is shared by every `ScreenClient`, so opening reports in several windows or
/// accounts cannot create an unbounded collection of in-flight temporary files.
actor ScreenReportOperationLimiter {
    static let shared = ScreenReportOperationLimiter(maximumConcurrentOperations: 2)

    private let maximumConcurrentOperations: Int
    private var activeOperations = 0
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Void, any Error>)] = []

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

        try await withCheckedThrowingContinuation { continuation in
            waiters.append((id, continuation))
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
        activeOperations -= 1
    }
}
