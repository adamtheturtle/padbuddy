//
//  PadBuddyTests+FocusScopeStackRestoration.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Focus scope stack restoration")
struct FocusScopeStackRestorationTests {
    private struct DecodeFailure: LocalizedError {
        var errorDescription: String? {
            "Damaged stack"
        }
    }

    @Test func `decode failure retains Focus restoration context`() {
        let outcome = FocusScopeStackRestoration.decode(
            Data(),
            expectedSessionID: "session",
            using: { _ in throw DecodeFailure() }
        )

        guard case let .failed(message) = outcome else {
            Issue.record("Expected Focus scope restoration failure")
            return
        }

        #expect(message == "Could not restore the Focus account scope stack: Damaged stack")
    }

    @Test func `stale stacks are adopted into the live session`() throws {
        let account = UUID()
        var previous = FocusScopeStack(
            sessionID: "old-process",
            baseShowAll: true,
            baseAccountID: ""
        )
        previous.push(account, token: UUID())
        let data = try JSONEncoder().encode(previous)

        let outcome = FocusScopeStackRestoration.decode(data, expectedSessionID: "new-process")
        guard case let .stale(stack) = outcome else {
            Issue.record("Expected a stale Focus scope stack from the previous process")
            return
        }

        let adopted = FocusScopeStackRestoration.adopt(stack, sessionID: "new-process")
        #expect(adopted.sessionID == "new-process")
        #expect(adopted.baseShowAll)
        #expect(adopted.imposedAccountID == account)
    }

    @Test func `deactivation keeps scoping when another Focus remains`() {
        let remaining = UUID()
        #expect(
            FocusDeactivationDecision.decide(remainingActiveAccount: remaining, hasStack: true)
                == .keepScoping(remaining)
        )
        #expect(FocusDeactivationDecision.decide(remainingActiveAccount: nil, hasStack: true) == .restoreBase)
        #expect(FocusDeactivationDecision.decide(remainingActiveAccount: nil, hasStack: false) == .noChange)
    }
}
