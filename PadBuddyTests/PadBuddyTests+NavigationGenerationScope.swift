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
