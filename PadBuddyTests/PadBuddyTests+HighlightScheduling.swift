//
//  PadBuddyTests+HighlightScheduling.swift
//  PadBuddyTests
//

@testable import PadBuddy
import Testing

@Suite("Highlight scheduling")
struct HighlightSchedulingTests {
    @Test
    func `cancelled input never reaches highlighting`() async {
        let task = Task { await HighlightScheduling.waitForSettledInput() }
        task.cancel()
        let settled = await task.value

        #expect(!settled)
    }
}
