//
//  coderpadTests+DockBadgeCompletion.swift
//  coderpadTests
//

@testable import coderpad
import Testing

@Suite("Dock badge completion ordering")
struct DockBadgeCompletionTests {
    @Test
    func `stale completions reassert the current desired badge`() {
        #expect(badgeCompletionAction(requestGeneration: 3, currentGeneration: 4, failed: false) == .reassertCurrent)
        #expect(badgeCompletionAction(requestGeneration: 3, currentGeneration: 4, failed: true) == .reassertCurrent)
    }

    @Test
    func `only a current failed write clears the badge`() {
        #expect(
            badgeCompletionAction(requestGeneration: 4, currentGeneration: 4, failed: true) == .clearCurrentAfterFailure
        )
        #expect(badgeCompletionAction(requestGeneration: 4, currentGeneration: 4, failed: false) == .noChange)
    }
}
