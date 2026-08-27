//
//  PadBuddyTests+CloudSyncIdentity.swift
//  PadBuddyTests
//
//  Tests for `Account.syncID`, the stable cross-device identity that keys every
//  iCloud-synced blob (#536). Split out of `PadBuddyTests+CloudSync.swift`, which
//  covers the merge helpers, to keep both files under the file-length limit.
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Cloud sync account identity")
struct CloudSyncIdentityTests {
    private func account(email: String, baseURL: String? = nil, apiKey: String = "key", id: UUID = UUID()) -> Account {
        Account(name: "Acme", apiKey: apiKey, id: id, userEmail: email, baseURL: baseURL)
    }

    @Test
    func `the sync id is identical across devices despite different local UUIDs`() {
        let deviceA = account(email: "jane@acme.com", id: UUID())
        let deviceB = account(email: "jane@acme.com", id: UUID())

        #expect(deviceA.id != deviceB.id)
        #expect(deviceA.syncID == deviceB.syncID)
        #expect(!deviceA.syncID.isEmpty)
    }

    @Test
    func `the sync id folds case and whitespace in the email`() {
        let plain = account(email: "jane@acme.com")
        let messy = account(email: "  Jane@Acme.com  ")
        #expect(plain.syncID == messy.syncID)
    }

    @Test
    func `different owners or servers get different sync ids`() {
        let jane = account(email: "jane@acme.com")
        let bob = account(email: "bob@acme.com")
        let janeSelfHosted = account(email: "jane@acme.com", baseURL: "https://coderpad.acme.internal")
        let janeSelfHostedPort = account(email: "jane@acme.com", baseURL: "https://coderpad.acme.internal:8443")
        let janeSelfHostedPath = account(email: "jane@acme.com", baseURL: "https://coderpad.acme.internal/org-a")

        #expect(jane.syncID != bob.syncID)
        #expect(jane.syncID != janeSelfHosted.syncID)
        #expect(janeSelfHosted.syncID != janeSelfHostedPort.syncID)
        #expect(janeSelfHosted.syncID != janeSelfHostedPath.syncID)
    }

    @Test
    func `endpoints that differ only in path spelling share one sync id`() {
        let plain = account(email: "jane@acme.com", baseURL: "https://coderpad.acme.internal/api")
        let doubled = account(email: "jane@acme.com", baseURL: "https://coderpad.acme.internal//api//")
        let dotted = account(email: "jane@acme.com", baseURL: "https://coderpad.acme.internal/api/./v1/../")
        let climbing = account(email: "jane@acme.com", baseURL: "https://coderpad.acme.internal/../api")
        // `URL.path` percent-decodes, so an encoded spelling of the same path lands
        // on the same identity rather than forking cloud state (#2143).
        let encoded = account(email: "jane@acme.com", baseURL: "https://coderpad.acme.internal/%61pi")

        #expect(plain.syncID == doubled.syncID)
        #expect(plain.syncID == dotted.syncID)
        #expect(plain.syncID == climbing.syncID)
        #expect(plain.syncID == encoded.syncID)
    }

    @Test
    func `an explicit default HTTPS port shares the implicit endpoint identity`() {
        let implicit = account(email: "jane@acme.com", baseURL: "https://coderpad.acme.internal/api")
        let explicit = account(email: "jane@acme.com", baseURL: "https://coderpad.acme.internal:443/api")
        let custom = account(email: "jane@acme.com", baseURL: "https://coderpad.acme.internal:8443/api")

        #expect(implicit.syncID == explicit.syncID)
        #expect(implicit.syncID != custom.syncID)
    }

    @Test
    func `rotating an API key preserves the sync id`() {
        let before = account(email: "jane@acme.com", apiKey: "old-key")
        let after = account(email: "jane@acme.com", apiKey: "rotated-key")

        #expect(before.syncID == after.syncID)
    }

    @Test
    func `an account with no owner email has an empty sync id`() {
        #expect(account(email: "").syncID.isEmpty)
        #expect(account(email: "   ").syncID.isEmpty)
        #expect(account(email: "jane@acme.com", apiKey: "   ").syncID.isEmpty)
    }
}

@Suite("Widget account identity")
struct WidgetAccountIdentityTests {
    @Test func `identity survives local restoration and API key rotation`() {
        let first = Account(name: "Acme", apiKey: "old", userEmail: "me@example.com")
        let restored = Account(name: "Restored", apiKey: "new", userEmail: "me@example.com")
        #expect(first.id != restored.id)
        #expect(WidgetAccountIdentity.identifier(for: first) == WidgetAccountIdentity.identifier(for: restored))
        #expect(WidgetAccountIdentity.resolve(WidgetAccountIdentity.identifier(for: first),
                                              accounts: [restored])?.id == restored.id)
        #expect(WidgetAccountIdentity.resolve(restored.id.uuidString, accounts: [restored])?.id == restored.id)
    }

    @Test func `legacy widget account JSON remains decodable`() throws {
        let data = Data(#"{"id":"legacy","name":"Acme"}"#.utf8)
        let account = try JSONDecoder().decode(WidgetAccount.self, from: data)
        #expect(account.id == "legacy")
        #expect(account.legacyID == nil)
    }
}

@Suite("Cloud sync identity index")
struct AccountSyncIdentityIndexTests {
    @Test func `builds forward and reverse indexes and omits incomplete accounts`() {
        let complete = Account(name: "Complete", apiKey: "key", userEmail: "me@example.com")
        let incomplete = Account(name: "Draft", apiKey: "key", userEmail: "")
        let index = AccountSyncIdentityIndex(accounts: [complete, incomplete])
        #expect(index.syncIDsByAccountID == [complete.id: complete.syncID])
        #expect(index.accountIDsBySyncID == [complete.syncID: complete.id])
    }

    @Test func `duplicate identities resolve deterministically to the first account`() {
        let first = Account(name: "First", apiKey: "one", userEmail: "same@example.com")
        let second = Account(name: "Second", apiKey: "two", userEmail: "same@example.com")
        let index = AccountSyncIdentityIndex(accounts: [first, second])
        #expect(first.syncID == second.syncID)
        #expect(index.accountIDsBySyncID[first.syncID] == first.id)
        #expect(index.syncIDsByAccountID[second.id] == second.syncID)
    }
}
