//
//  PadBuddyTests+WidgetClaimAcknowledgement.swift
//  PadBuddyTests
//

import Foundation
import Testing
@testable import PadBuddy

@Suite("Widget claim acknowledgement")
struct WidgetClaimAcknowledgementTests {
    private struct AcknowledgeFailure: LocalizedError {
        var errorDescription: String? { "Mailbox unavailable" }
    }

    @Test func `failure includes the cleanup operation context`() {
        let failure = WidgetSharedStore.acknowledgementFailure(
            context: "Could not acknowledge an excess widget handoff request",
            acknowledge: { throw AcknowledgeFailure() }
        )

        #expect(failure == "Could not acknowledge an excess widget handoff request: Mailbox unavailable")
    }
}
