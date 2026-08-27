//
//  PadBuddyTests+AppReadinessTimeout.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("App readiness timeout")
struct AppReadinessTimeoutTests {
    private struct WaitFailure: LocalizedError {
        var errorDescription: String? {
            "Clock unavailable"
        }
    }

    @Test func `timeout cancellation remains distinct`() async {
        let outcome = await AppReadinessTimeout.wait(for: .zero) { _ in throw CancellationError() }

        guard case .cancelled = outcome else {
            Issue.record("Expected cancelled timeout")
            return
        }
    }

    @Test func `unexpected timeout failure retains operation context`() async {
        let outcome = await AppReadinessTimeout.wait(for: .zero) { _ in throw WaitFailure() }

        guard case let .failed(message) = outcome else {
            Issue.record("Expected failed timeout")
            return
        }

        #expect(message == "App readiness timeout failed: Clock unavailable")
    }
}

@Suite("App readiness waiting (#4590, #4591)", .serialized)
@MainActor
struct AppReadinessWaitTests {
    @Test func `the wait returns after its timeout when no scene ever mounts`() async throws {
        guard !AppReadiness.isReady else { return }

        let started = ContinuousClock.now
        try await AppReadiness.waitUntilReady(timeout: .milliseconds(50))

        // It used to hang here: the timeout child won the race, but leaving the task
        // group waited on a readiness continuation nothing could resume.
        #expect(ContinuousClock.now - started < .seconds(5))
        #expect(AppReadiness.waiterCount == 0)
    }

    @Test func `a cancelled caller returns instead of waiting for a scene`() async throws {
        guard !AppReadiness.isReady else { return }

        let task = Task {
            try await AppReadiness.waitUntilReady(timeout: .seconds(600))
        }
        // Let the wait install its continuation before cancelling it.
        while AppReadiness.waiterCount == 0 {
            try await Task.sleep(for: .milliseconds(1))
        }

        task.cancel()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(AppReadiness.waiterCount == 0)
    }

    @Test func `a cancelled wait leaves no waiter behind`() async throws {
        guard !AppReadiness.isReady else { return }

        for _ in 0 ..< 3 {
            let task = Task { try await AppReadiness.waitUntilReady(timeout: .seconds(600)) }
            while AppReadiness.waiterCount == 0 {
                try await Task.sleep(for: .milliseconds(1))
            }
            task.cancel()
            _ = try? await task.value
        }

        #expect(AppReadiness.waiterCount == 0)
    }
}
