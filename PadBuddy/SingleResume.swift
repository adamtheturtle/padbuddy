//
//  SingleResume.swift
//  coderpad
//
//  Racing an operation against a deadline without waiting for the loser.
//

import Foundation
import os

/// Resumes a continuation exactly once, for whichever racing outcome arrives first; every
/// later one is a no-op.
///
/// A `withTaskGroup` race reads more naturally, but leaving a task group waits for every
/// child, so `cancelAll()` does not end the wait if a child ignores or delays
/// cancellation — the timeout then bounds nothing at all. Racing through this box instead
/// returns at the deadline and abandons the loser to finish on its own.
final nonisolated class SingleResume<Value: Sendable>: @unchecked Sendable {
    private struct State {
        var continuation: CheckedContinuation<Value, Never>?
        var result: Value?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    init() {}

    /// Whether an outcome has already been recorded, so a caller can skip work whose
    /// result would be discarded.
    var isFinished: Bool {
        state.withLock { $0.result != nil }
    }

    /// Hands the continuation over, resuming immediately if the race is already decided.
    func attach(_ continuation: CheckedContinuation<Value, Never>) {
        let settled = state.withLock { state -> Value? in
            guard let result = state.result else {
                state.continuation = continuation
                return nil
            }

            return result
        }
        if let settled {
            continuation.resume(returning: settled)
        }
    }

    /// Records an outcome. The first call wins and resumes the continuation if it has
    /// already been attached; the rest do nothing.
    func finish(_ value: Value) {
        let continuation = state.withLock { state -> CheckedContinuation<Value, Never>? in
            guard state.result == nil else { return nil }

            state.result = value
            defer { state.continuation = nil }
            return state.continuation
        }
        continuation?.resume(returning: value)
    }
}
