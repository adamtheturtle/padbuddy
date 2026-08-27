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
