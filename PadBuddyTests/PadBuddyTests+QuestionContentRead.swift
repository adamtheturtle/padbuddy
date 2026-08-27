//
//  PadBuddyTests+QuestionContentRead.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Question content safety read")
struct QuestionContentReadTests {
    private struct ReadFailure: LocalizedError {
        var errorDescription: String? {
            "Server unavailable"
        }
    }

    @Test func `read failure blocks the save with contextual feedback`() async throws {
        let outcome: QuestionContentReadOutcome<String> = try await QuestionContentRead.evaluate {
            throw ReadFailure()
        }

        guard case let .failed(message) = outcome else {
            Issue.record("Expected a failed safety read")
            return
        }

        #expect(message == "Could not check the latest question — Server unavailable")
    }

    @Test func `cancelled read remains cancellation`() async {
        do {
            let _: QuestionContentReadOutcome<String> = try await QuestionContentRead.evaluate {
                throw CancellationError()
            }
            Issue.record("Expected cancellation")
        } catch is CancellationError {
            // Expected: cancellation is not converted into a read failure.
        } catch {
            Issue.record("Expected CancellationError, got \(error)")
        }
    }
}
