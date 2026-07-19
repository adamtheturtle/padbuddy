//
//  coderpadTests+HighlightScheduling.swift
//  coderpadTests
//

@testable import CoderPad
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
