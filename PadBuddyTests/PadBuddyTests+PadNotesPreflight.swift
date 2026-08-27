//
//  PadBuddyTests+PadNotesPreflight.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Pad notes save preflight")
struct PadNotesPreflightTests {
    private struct ReadFailure: LocalizedError {
        var errorDescription: String? {
            "Server unavailable"
        }
    }

    @Test func `failed safety read blocks save with contextual feedback`() async throws {
        let outcome = try await PadNotesPreflight.evaluate(
            source: "original",
            load: { throw ReadFailure() },
            notes: { (_: String) in "" }
        )
        guard case let .failed(message) = outcome else {
            Issue.record("Expected a failed preflight")
            return
        }

        #expect(message == "Could not check the latest interviewer notes — Server unavailable")
    }

    @Test func `cancelled safety read remains cancellation`() async {
        do {
            _ = try await PadNotesPreflight.evaluate(
                source: "original",
                load: { throw CancellationError() },
                notes: { (_: String) in "" }
            )
            Issue.record("Expected cancellation")
        } catch is CancellationError {
            // Expected: callers distinguish cancellation from a failed safety read.
        } catch {
            Issue.record("Expected CancellationError, got \(error)")
        }
    }
}
