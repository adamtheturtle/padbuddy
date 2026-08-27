//
//  PadBuddyTests+BulkDeleteGrace.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Bulk-delete grace timer")
struct BulkDeleteGraceTests {
    private struct TimerFailure: Error {}

    @Test func `cancellation remains cancellation`() async {
        await #expect(throws: CancellationError.self) {
            try await BulkDeleteUndo.waitForGrace { throw CancellationError() }
        }
    }

    @Test func `unexpected timer failure remains observable`() async {
        await #expect(throws: TimerFailure.self) {
            try await BulkDeleteUndo.waitForGrace { throw TimerFailure() }
        }
    }
}
