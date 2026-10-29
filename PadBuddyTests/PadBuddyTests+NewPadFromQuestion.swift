//
//  PadBuddyTests+NewPadFromQuestion.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("New Pad from Question validation")
struct NewPadFromQuestionValidationTests {
    @Test func `only the freshly fetched requested question is accepted`() throws {
        let requested = try CoderPadClient.decoder.decode(
            Question.self, from: Data(#"{"id":42,"title":"Fresh"}"#.utf8)
        )
        let wrong = try CoderPadClient.decoder.decode(
            Question.self, from: Data(#"{"id":43,"title":"Wrong"}"#.utf8)
        )
        #expect(NewPadFromQuestionValidation.accept(requestedID: 42, fetched: requested)?.id == 42)
        #expect(NewPadFromQuestionValidation.accept(requestedID: 42, fetched: wrong) == nil)
    }

    @Test @MainActor func `inline and menu creation claims share account-qualified exclusion`() throws {
        let account = UUID(), otherAccount = UUID()
        let key = try #require(NewPadFromQuestionRunner.claimCreation(accountID: account, questionID: 42))
        defer { NewPadFromQuestionRunner.finishCreation(key) }
        #expect(NewPadFromQuestionRunner.claimCreation(accountID: account, questionID: 42) == nil)
        let other = try #require(NewPadFromQuestionRunner.claimCreation(accountID: otherAccount, questionID: 42))
        NewPadFromQuestionRunner.finishCreation(other)
        NewPadFromQuestionRunner.finishCreation(key)
        let retry = try #require(NewPadFromQuestionRunner.claimCreation(accountID: account, questionID: 42))
        NewPadFromQuestionRunner.finishCreation(retry)
    }

    @Test
    func `palette account resolution uses the current same-ID credentials`() {
        let id = UUID()
        let stale = Account(name: "Old", apiKey: "old-key", id: id,
                            userEmail: "me@example.com", baseURL: "https://old.example.com")
        let current = Account(name: "New", apiKey: "new-key", id: id,
                              userEmail: "me@example.com", baseURL: "https://new.example.com")

        let resolved = NewPadFromQuestionRunner.resolveAccount(id: stale.id, in: [current])
        #expect(resolved?.apiKey == "new-key")
        #expect(resolved?.baseURL == "https://new.example.com")
        #expect(NewPadFromQuestionRunner.resolveAccount(id: stale.id, in: []) == nil)
    }
}
