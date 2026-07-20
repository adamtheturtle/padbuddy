//
//  coderpadTests+AccountEditDrafts.swift
//  coderpadTests
//

@testable import CoderPad
import Foundation
import Testing

@MainActor
@Suite("Account edit draft recovery")
struct AccountEditDraftTests {
    @Test func `an unsaveable draft resumes against the account it edited`() {
        let saved = Account(name: "Acme", apiKey: "old", userEmail: "me@acme.test")
        var draft = saved
        draft.apiKey = "incomplete replacement"

        AccountEditDrafts.shared.stash(draft, persisted: saved)

        #expect(AccountEditDrafts.shared.resume(for: saved)?.apiKey == "incomplete replacement")
        #expect(AccountEditDrafts.shared.resume(for: saved) == nil)
    }

    @Test func `a draft is discarded when the saved account changed elsewhere`() {
        let saved = Account(name: "Acme", apiKey: "old", userEmail: "me@acme.test")
        var draft = saved
        draft.apiKey = "draft"
        var externallyChanged = saved
        externallyChanged.name = "Renamed"

        AccountEditDrafts.shared.stash(draft, persisted: saved)

        #expect(AccountEditDrafts.shared.resume(for: externallyChanged) == nil)
        #expect(AccountEditDrafts.shared.resume(for: saved) == nil)
    }

    @Test func `an immediate appearance save does not invalidate the text draft`() {
        let saved = Account(name: "Acme", apiKey: "old", userEmail: "me@acme.test")
        var draft = saved
        draft.apiKey = "draft"
        var recolored = saved
        recolored.tintHex = "#123456"

        AccountEditDrafts.shared.stash(draft, persisted: saved)

        #expect(AccountEditDrafts.shared.resume(for: recolored)?.apiKey == "draft")
    }

    @Test func `clearing an account purges its draft`() {
        let saved = Account(name: "Acme", apiKey: "old", userEmail: "me@acme.test")
        AccountEditDrafts.shared.stash(saved, persisted: saved)

        AccountEditDrafts.shared.clear(account: saved.id)

        #expect(AccountEditDrafts.shared.resume(for: saved) == nil)
    }
}
