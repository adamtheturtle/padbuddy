//
//  AppReadiness.swift
//  coderpad
//
//  A readiness signal for App Intents, replacing the fixed warm-up sleeps they used
//  to take before writing navigation state (#2356).
//
//  Every intent slept 200–400ms on the theory that a cold launch needs time to put a
//  view on screen. That was wrong in both directions: a slow launch still missed the
//  window, and a launch that was already warm — by far the common case, since running
//  a shortcut for an app you are using does not relaunch it — paid the full delay and
//  spent it inside a window where Shortcuts can cancel the intent. Waiting on the
//  actual signal is both faster and more reliable.
//

import Foundation

nonisolated enum AppReadinessTimeoutOutcome {
    case elapsed
    case cancelled
    case failed(String)
}

nonisolated enum AppReadinessTimeout {
    static func wait(
        for duration: Duration,
        using sleep: ((Duration) async throws -> Void)? = nil
    ) async -> AppReadinessTimeoutOutcome {
        do {
            if let sleep {
                try await sleep(duration)
            } else {
                try await Task.sleep(for: duration)
            }
            return .elapsed
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failed("App readiness timeout failed: \(error.localizedDescription)")
        }
    }
}

/// Tracks whether a scene root has appeared, so an intent can route as soon as there
/// is something to route to.
@MainActor
enum AppReadiness {
    private(set) static var isReady = false
    private static var waiters: [CheckedContinuation<Void, Never>] = []

    /// Called from the scene root's `onAppear`. Idempotent — several windows, or one
    /// window re-appearing, resolve the same single signal.
    static func markReady() {
        guard !isReady else { return }

        isReady = true
        let resuming = waiters
        waiters = []
        for waiter in resuming {
            waiter.resume()
        }
    }

    /// Returns as soon as a scene root has appeared, or after `timeout` regardless.
    ///
    /// The timeout is a backstop, not the mechanism: navigation state is durable and
    /// consumed on appear, so routing slightly early is survivable, and it is better
    /// than an intent that never returns if a scene somehow never mounts. Throws
    /// `CancellationError` when Shortcuts or Siri cancels the intent, so the caller
    /// exits before routing (#844).
    static func waitUntilReady(timeout: Duration = .milliseconds(1500)) async throws {
        if isReady {
            try Task.checkCancellation()
            return
        }

        let first = await withTaskGroup(of: AppReadinessTimeoutOutcome.self) { group in
            group.addTask {
                await signalled()
                return .elapsed
            }
            group.addTask { await AppReadinessTimeout.wait(for: timeout) }
            let first = await group.next() ?? .failed("App readiness race ended without a result")
            group.cancelAll()
            return first
        }
        if case .cancelled = first { throw CancellationError() }
        if case let .failed(message) = first { assertionFailure(message) }
        try Task.checkCancellation()
    }

    private static func signalled() async {
        await withCheckedContinuation { continuation in
            if isReady {
                continuation.resume()
            } else {
                waiters.append(continuation)
            }
        }
    }
}
