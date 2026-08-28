//
//  PadBuddyTests+NavigationGenerationScope.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Navigation generation scope")
struct NavigationGenerationScopeTests {
    private func identities() throws -> (old: ClientTaskIdentity, new: ClientTaskIdentity) {
        try (
            ClientTaskIdentity(apiKey: "old", baseURL: #require(URL(string: "https://old.example"))),
            ClientTaskIdentity(apiKey: "new", baseURL: #require(URL(string: "https://new.example")))
        )
    }

    @Test
    func `newer pad selection replaces its complete scope`() throws {
        let identity = try identities()
        let newAccount = UUID()
        let merged = AppNavigation.merged(
            pending: PadsRequest(
                selectPadID: "old-pad", selectPadAccountID: UUID(), selectPadClientIdentity: identity.old
            ),
            incoming: PadsRequest(
                selectPadID: "new-pad", selectPadAccountID: newAccount,
                selectPadClientIdentity: identity.new
            )
        )

        #expect(merged.selectPadID == "new-pad")
        #expect(merged.selectPadAccountID == newAccount)
        #expect(merged.selectPadClientIdentity == identity.new)
    }

    @Test
    func `newer question selection replaces its complete scope`() throws {
        let identity = try identities()
        let newAccount = UUID()
        let merged = AppNavigation.merged(
            pending: QuestionsRequest(
                selectQuestionID: 1, selectQuestionAccountID: UUID(),
                selectQuestionClientIdentity: identity.old
            ),
            incoming: QuestionsRequest(
                selectQuestionID: 2, selectQuestionAccountID: newAccount,
                selectQuestionClientIdentity: identity.new
            )
        )

        #expect(merged.selectQuestionID == 2)
        #expect(merged.selectQuestionAccountID == newAccount)
        #expect(merged.selectQuestionClientIdentity == identity.new)
    }
}

@Suite("Command target backend identity (#4774)")
@MainActor
struct CommandTargetIdentityTests {
    @Test func `a target naming no account always applies`() {
        // Such a command applies to whatever the pane is showing, so there is no backend
        // to compare against.
        #expect(commandTargetIsCurrent(account: nil, clientIdentity: nil))
    }

    @Test func `a target whose account no longer resolves is stale`() throws {
        let baseURL = try #require(URL(string: "https://coderpad.io"))
        let identity = ClientTaskIdentity(apiKey: "key", baseURL: baseURL)

        #expect(!commandTargetIsCurrent(account: UUID(), clientIdentity: identity))
    }

    @Test func `a target captures the identity of the account it names`() {
        let target = AppNavigation.PadCommandTarget(id: "pad", account: nil)

        #expect(target.clientIdentity == nil)
        #expect(target.id == "pad")
    }

    @Test func `question targets carry the same identity`() {
        let target = AppNavigation.QuestionCommandTarget(id: 7, account: nil)

        #expect(target.clientIdentity == nil)
        #expect(target.id == 7)
    }
}
