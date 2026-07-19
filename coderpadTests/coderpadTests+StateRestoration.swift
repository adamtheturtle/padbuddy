//
//  coderpadTests+StateRestoration.swift
//  coderpadTests
//
//  Unit coverage for the launch-time selection-restore decision (#273): which saved
//  pad/question, if any, should be reselected once the list has loaded. The decision
//  is a pure function so it's testable without standing up a SwiftUI view.
//

@testable import CoderPad
import Foundation
import Testing

@MainActor
struct SelectionRestoreTests {
    @Test func `restores the saved pad when nothing blocks it`() {
        let target = PadsView.padToRestore(
            savedID: "p2", hasSelection: false, hasPendingOpen: false,
            availableIDs: ["p1", "p2", "p3"]
        )
        #expect(target == "p2")
    }

    @Test func `does not restore a pad when one is already selected`() {
        let target = PadsView.padToRestore(
            savedID: "p2", hasSelection: true, hasPendingOpen: false,
            availableIDs: ["p1", "p2"]
        )
        #expect(target == nil)
    }

    @Test func `does not restore a pad while a deep link is pending`() {
        let target = PadsView.padToRestore(
            savedID: "p2", hasSelection: false, hasPendingOpen: true,
            availableIDs: ["p1", "p2"]
        )
        #expect(target == nil)
    }

    @Test func `does not restore a pad missing from the loaded list`() {
        let target = PadsView.padToRestore(
            savedID: "gone", hasSelection: false, hasPendingOpen: false,
            availableIDs: ["p1", "p2"]
        )
        #expect(target == nil)
    }

    @Test func `does not restore a pad when nothing was saved`() {
        let target = PadsView.padToRestore(
            savedID: nil, hasSelection: false, hasPendingOpen: false,
            availableIDs: ["p1", "p2"]
        )
        #expect(target == nil)
    }

    @Test func `restores the saved question when nothing blocks it`() {
        let target = QuestionsView.questionToRestore(
            savedID: 42, hasSelection: false, hasPendingNavigation: false,
            availableIDs: [7, 42, 99]
        )
        #expect(target == 42)
    }

    @Test func `does not restore a question while a navigation is pending`() {
        let target = QuestionsView.questionToRestore(
            savedID: 42, hasSelection: false, hasPendingNavigation: true,
            availableIDs: [7, 42]
        )
        #expect(target == nil)
    }

    @Test func `does not restore a question missing from the loaded list`() {
        let target = QuestionsView.questionToRestore(
            savedID: 1234, hasSelection: false, hasPendingNavigation: false,
            availableIDs: [7, 42]
        )
        #expect(target == nil)
    }

    // The combined (all-accounts) list keys its selection by an account-namespaced
    // row id, since per-org question ids collide across accounts. The restore
    // decision is otherwise identical to the single-account one.

    @Test func `restores the saved merged row when nothing blocks it`() {
        let target = MergedQuestionsView.rowToRestore(
            savedRowID: "acct-b:42", hasSelection: false, hasPendingNavigation: false,
            availableRowIDs: ["acct-a:42", "acct-b:42", "acct-b:7"]
        )
        #expect(target == "acct-b:42")
    }

    @Test func `does not restore a merged row when one is already selected`() {
        let target = MergedQuestionsView.rowToRestore(
            savedRowID: "acct-b:42", hasSelection: true, hasPendingNavigation: false,
            availableRowIDs: ["acct-b:42"]
        )
        #expect(target == nil)
    }

    @Test func `does not restore a merged row while a favorite navigation is pending`() {
        let target = MergedQuestionsView.rowToRestore(
            savedRowID: "acct-b:42", hasSelection: false, hasPendingNavigation: true,
            availableRowIDs: ["acct-b:42"]
        )
        #expect(target == nil)
    }

    @Test func `does not restore a merged row missing from the loaded list`() {
        let target = MergedQuestionsView.rowToRestore(
            savedRowID: "acct-b:42", hasSelection: false, hasPendingNavigation: false,
            availableRowIDs: ["acct-a:42", "acct-b:7"]
        )
        #expect(target == nil)
    }

    @Test func `does not restore a merged row when nothing was saved`() {
        let target = MergedQuestionsView.rowToRestore(
            savedRowID: nil, hasSelection: false, hasPendingNavigation: false,
            availableRowIDs: ["acct-b:42"]
        )
        #expect(target == nil)
    }
}

struct FocusFilterRestoreTests {
    @Test func `restores a saved nil account selection (#756)`() {
        let account = Account(name: "Acme", apiKey: "key", userEmail: "a@example.com")
        let restored = FocusFilterRestoredAccount.resolve(
            savedID: FocusFilterRestoredAccount.noAccountMarker,
            accounts: [account]
        )

        #expect(restored == .noAccount)
    }

    @Test func `restores a saved current account when it still exists`() {
        let id = UUID()
        let account = Account(name: "Acme", apiKey: "key", id: id, userEmail: "a@example.com")

        #expect(FocusFilterRestoredAccount.resolve(savedID: id.uuidString, accounts: [account]) == .account(id))
    }

    @Test func `ignores a missing or stale saved focus account`() {
        let account = Account(name: "Acme", apiKey: "key", userEmail: "a@example.com")

        #expect(FocusFilterRestoredAccount.resolve(savedID: nil, accounts: [account]) == .missingSnapshot)
        #expect(FocusFilterRestoredAccount.resolve(savedID: UUID().uuidString, accounts: [account]) == .missingSnapshot)
    }
}

struct FocusFilterActionTests {
    private let account = Account(name: "Acme", apiKey: "key", userEmail: "a@example.com")

    @Test func `a resolvable configured account scopes`() {
        let action = FocusFilterAction.decide(
            configuredID: AccountFocusIdentity.identifier(for: account), accounts: [account], hasSnapshot: false
        )
        #expect(action == .scope(account.id))
    }

    @Test func `stable identity resolves a restored account with a new local UUID`() {
        let restored = Account(name: "Acme restored", apiKey: account.apiKey,
                               userEmail: account.userEmail, baseURL: account.baseURL)
        #expect(restored.id != account.id)
        #expect(AccountFocusIdentity.identifier(for: restored) == AccountFocusIdentity.identifier(for: account))
        #expect(AccountFocusIdentity.resolve(AccountFocusIdentity.identifier(for: account),
                                             accounts: [restored])?.id == restored.id)
    }

    @Test func `legacy UUID and incomplete-identity fallback remain resolvable`() {
        let legacy = Account(name: "Legacy", apiKey: "key", userEmail: "")
        #expect(AccountFocusIdentity.identifier(for: legacy) == legacy.id.uuidString)
        #expect(AccountFocusIdentity.resolve(account.id.uuidString, accounts: [account])?.id == account.id)
        #expect(AccountFocusIdentity.resolve(legacy.id.uuidString, accounts: [legacy])?.id == legacy.id)
    }

    @Test func `a removed configured account is stale, not Focus off (#796)`() {
        let action = FocusFilterAction.decide(
            configuredID: UUID().uuidString, accounts: [account], hasSnapshot: true
        )
        #expect(action == .staleScope)
    }

    @Test func `no configured account restores only when a snapshot exists`() {
        #expect(FocusFilterAction.decide(configuredID: nil, accounts: [account], hasSnapshot: true) == .restore)
        #expect(FocusFilterAction.decide(configuredID: nil, accounts: [account], hasSnapshot: false) == .noChange)
    }
}

struct FocusFilterSnapshotTests {
    private let account = Account(name: "Acme", apiKey: "key", userEmail: "a@example.com")

    @Test func `requires both snapshot fields`() {
        #expect(FocusFilterSnapshot.resolve(savedShowAll: nil, savedCurrentID: nil, accounts: [account]) == .absent)
        #expect(FocusFilterSnapshot.resolve(
            savedShowAll: true, savedCurrentID: nil, accounts: [account]
        ) == .incomplete)
        #expect(FocusFilterSnapshot.resolve(
            savedShowAll: nil, savedCurrentID: "", accounts: [account]
        ) == .incomplete)
    }

    @Test func `requires the saved account to remain restorable`() {
        #expect(FocusFilterSnapshot.resolve(
            savedShowAll: false,
            savedCurrentID: UUID().uuidString,
            accounts: [account]
        ) == .incomplete)
    }

    @Test func `keeps a complete atomic selection`() {
        #expect(FocusFilterSnapshot.resolve(
            savedShowAll: true,
            savedCurrentID: account.id.uuidString,
            accounts: [account]
        ) == .complete(showAll: true, account: .account(account.id)))
        #expect(FocusFilterSnapshot.resolve(
            savedShowAll: false,
            savedCurrentID: FocusFilterRestoredAccount.noAccountMarker,
            accounts: [account]
        ) == .complete(showAll: false, account: .noAccount))
    }
}
