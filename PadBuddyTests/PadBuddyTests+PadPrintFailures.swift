//
//  PadBuddyTests+PadPrintFailures.swift
//  PadBuddyTests
//

import Foundation
import Testing
@testable import PadBuddy

@Suite("Pad printing failures")
struct PadPrintFailureTests {
    private struct PrintFailure: LocalizedError {
        var errorDescription: String? { "Printer unavailable" }
    }

    @Test func `printing failure becomes an action alert`() {
        #expect(padPrintFailureMessage(for: PrintFailure()) == "Printer unavailable")
    }

    @Test func `printing cancellation does not become an error alert`() {
        #expect(padPrintFailureMessage(for: CancellationError()) == nil)
    }
}
