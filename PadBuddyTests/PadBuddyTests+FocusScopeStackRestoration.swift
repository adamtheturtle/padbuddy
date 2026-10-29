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

@Suite("Focus scope reset")
struct FocusScopeStackResetTests {
    @Test func `reset restores the base while Focus still owns selection`() {
        let base = UUID()
        let imposed = UUID()
        var stack = FocusScopeStack(
            sessionID: "session",
            baseShowAll: false,
            baseAccountID: base.uuidString
        )
        stack.push(imposed)

        #expect(FocusScopeStackReset.selection(
            for: stack,
            currentShowAll: false,
            currentAccountID: imposed
        ) == FocusScopeResetSelection(showAll: false, accountID: base))
    }

    @Test func `reset preserves a later user selection`() {
        let imposed = UUID()
        var stack = FocusScopeStack(
            sessionID: "session",
            baseShowAll: true,
            baseAccountID: FocusFilterRestoredAccount.noAccountMarker
        )
        stack.push(imposed)

        #expect(FocusScopeStackReset.selection(
            for: stack,
            currentShowAll: false,
            currentAccountID: UUID()
        ) == nil)
    }
}

@Suite("Focus scope stack bounds (#4731, #4732)")
struct FocusScopeStackBoundsTests {
    private func stack() -> FocusScopeStack {
        FocusScopeStack(sessionID: "session", baseShowAll: false, baseAccountID: UUID().uuidString)
    }

    @Test func `repeating the same activation does not stack another scope`() {
        var stack = stack()
        let account = UUID()

        let token = UUID()
        // Repeated delivery of one logical owner keeps its token.
        for _ in 0 ..< 50 {
            stack.push(account, token: token)
        }

        #expect(stack.scopes.count == 1)
        #expect(stack.imposedAccountID == account)
    }

    @Test func `genuinely nested scopes still stack`() {
        var stack = stack()
        let first = UUID()
        let second = UUID()

        stack.push(first)
        stack.push(second)

        #expect(stack.scopes.count == 2)
        #expect(stack.imposedAccountID == second)
        #expect(stack.pop()?.accountID == second)
        #expect(stack.imposedAccountID == first)
    }

    @Test func `nesting is capped and keeps the newest scopes`() {
        var stack = stack()
        let accounts = (0 ..< (FocusScopeStack.maximumScopes + 5)).map { _ in UUID() }

        for account in accounts {
            stack.push(account)
        }

        #expect(stack.scopes.count == FocusScopeStack.maximumScopes)
        #expect(stack.imposedAccountID == accounts.last)
    }

    @Test func `an account that cannot load is not scopable`() {
        #expect(!AccountFocusIdentity.isUsableForFocus(Account(name: "A", apiKey: "")))
        #expect(AccountFocusIdentity.isUsableForFocus(Account(name: "A", apiKey: "key")))
        #expect(AccountFocusIdentity.isUsableForFocus(Account(name: "A", apiKey: "", isMock: true)))
        #expect(!AccountFocusIdentity.isUsableForFocus(
            Account(name: "A", apiKey: "key", baseURL: "https://user:secret@example.com")
        ))
    }

    @Test func `a configured account that lost its key is stale, not scopable`() {
        let account = Account(name: "A", apiKey: "")

        let action = FocusFilterAction.decide(
            configuredID: account.id.uuidString, accounts: [account], hasSnapshot: false
        )

        #expect(action == .staleScope)
    }
}
