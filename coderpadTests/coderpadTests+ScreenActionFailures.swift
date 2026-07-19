//
//  coderpadTests+ScreenActionFailures.swift
//  coderpadTests
//

@testable import CoderPad
import Testing

@Suite("Screen action failure context")
struct ScreenActionFailureTests {
    @Test
    func `failure identifies operation candidate session and account`() {
        let failure = ScreenActionFailure(
            operation: "Cancel invitation",
            testID: 42,
            candidate: "Ada Lovelace",
            accountName: "Acme EU",
            reason: "The request timed out."
        )

        #expect(failure.detail.contains("Cancel invitation"))
        #expect(failure.detail.contains("Ada Lovelace"))
        #expect(failure.detail.contains("#42"))
        #expect(failure.detail.contains("Acme EU"))
        #expect(failure.detail.contains("The request timed out."))
    }
}
