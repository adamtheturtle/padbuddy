import Foundation

@concurrent
func cancellableValue<Value: Sendable>(
    of task: Task<Value, any Error>
) async throws -> Value {
    let waiter = CancellableTaskValueWaiter<Value>()
    Task {
        let result = await task.result
        waiter.resolve(with: result)
    }
    return try await waiter.value()
}

private final nonisolated class CancellableTaskValueWaiter<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, any Error>?
    private var result: Result<Value, any Error>?
    private var isCancelled = false

    func value() async throws -> Value {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                install(continuation)
            }
        } onCancel: {
            cancel()
        }
    }

    func resolve(with result: Result<Value, any Error>) {
        let continuation: CheckedContinuation<Value, any Error>?
        lock.lock()
        if isCancelled {
            continuation = nil
        } else if let waiting = self.continuation {
            self.continuation = nil
            continuation = waiting
        } else {
            self.result = result
            continuation = nil
        }
        lock.unlock()
        continuation?.resume(with: result)
    }

    private func install(_ continuation: CheckedContinuation<Value, any Error>) {
        let result: Result<Value, any Error>?
        let cancelled: Bool
        lock.lock()
        result = self.result
        self.result = nil
        cancelled = isCancelled
        if result == nil, !cancelled {
            self.continuation = continuation
        }
        lock.unlock()

        if cancelled {
            continuation.resume(throwing: CancellationError())
        } else if let result {
            continuation.resume(with: result)
        }
    }

    private func cancel() {
        let continuation: CheckedContinuation<Value, any Error>?
        lock.lock()
        guard !isCancelled else {
            lock.unlock()
            return
        }

        isCancelled = true
        continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(throwing: CancellationError())
    }
}
