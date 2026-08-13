//
//  PadBuddyTests+QuestionPrintFailures.swift
//  PadBuddyTests
//

import Foundation
import Testing
@testable import PadBuddy

@Suite("Question printing failures")
struct QuestionPrintFailureTests {
    private struct PrintFailure: LocalizedError {
        var errorDescription: String? { "Printer unavailable" }
    }

    @Test func `printing failure includes operation context for the alert`() {
        #expect(questionPrintFailureMessage(for: PrintFailure())
            == "Could not print this question — Printer unavailable")
    }

    @Test func `printing cancellation does not become an error alert`() {
        #expect(questionPrintFailureMessage(for: CancellationError()) == nil)
    }
}
