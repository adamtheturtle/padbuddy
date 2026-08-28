//
//  PadBuddyTests+CloudSyncIdentityCollisions.swift
//  PadBuddyTests
//
//  The cases where an account must not claim a cloud identity at all: a malformed
//  Server URL that would otherwise inherit the hosted one (#4801), and two accounts
//  resolving to the same identity (#4802).
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Cloud sync identity collisions")
struct CloudSyncIdentityCollisionTests {
    private func account(email: String, baseURL: String? = nil, apiKey: String = "key",
                         id: UUID = UUID()) -> Account {
        Account(name: "Acme", apiKey: apiKey, id: id, userEmail: email, baseURL: baseURL)
    }

    /// A self-hosted account mid-edit in Settings, or restored from a corrupt synced
    /// value, must not merge its cloud state into the user's hosted account under the
    /// same email.
    @Test func `a malformed server url yields no sync identity`() {
        let broken = account(email: "jane@acme.com", baseURL: "ht tp://coderpad acme")

        #expect(broken.hasMalformedBaseURLOverride)
        #expect(broken.syncID.isEmpty)
    }

    @Test func `a blank server url still selects the hosted identity`() {
        let hosted = account(email: "jane@acme.com", baseURL: "   ")

        #expect(!hosted.hasMalformedBaseURLOverride)
        #expect(hosted.syncID == account(email: "jane@acme.com").syncID)
    }

    @Test func `a malformed account is absent from both directions of the index`() {
        let broken = account(email: "jane@acme.com", baseURL: "ht tp://coderpad acme")

        let index = AccountSyncIdentityIndex(accounts: [broken])

        #expect(index.syncIDsByAccountID.isEmpty)
        #expect(index.accountIDsBySyncID.isEmpty)
    }

    /// Same server and owner email with different keys — a personal key and a service
    /// key for one org — produce one identity. Both used to mirror to it and overwrite
    /// each other, while only the first could ever read it back.
    @Test func `only the first claimant of a shared identity mirrors`() {
        let first = account(email: "jane@acme.com", apiKey: "personal")
        let second = account(email: "jane@acme.com", apiKey: "service")

        #expect(first.syncID == second.syncID)

        let index = AccountSyncIdentityIndex(accounts: [first, second])

        #expect(index.syncIDsByAccountID[first.id] == first.syncID)
        #expect(index.syncIDsByAccountID[second.id] == nil)
        #expect(index.accountIDsBySyncID[first.syncID] == first.id)
    }

    @Test func `distinct identities are all indexed`() {
        let jane = account(email: "jane@acme.com")
        let bob = account(email: "bob@acme.com")

        let index = AccountSyncIdentityIndex(accounts: [jane, bob])

        #expect(index.syncIDsByAccountID.count == 2)
        #expect(index.accountIDsBySyncID.count == 2)
    }
}

@Suite("Keychain revision stamps")
struct KeychainRevisionTests {
    private func data(_ text: String) -> Data {
        Data(text.utf8)
    }

    /// `TimeInterval("inf")` parses. An `inf` revision made every later local write
    /// produce the same stamp, so the poisoned cloud copy won every future merge
    /// (#4805).
    @Test func `non-finite stamps are rejected`() {
        #expect(Keychain.revision(from: data("inf")) == 0)
        #expect(Keychain.revision(from: data("-inf")) == 0)
        #expect(Keychain.revision(from: data("nan")) == 0)
    }

    @Test func `a stamp past the ceiling saturates`() {
        #expect(Keychain.revision(from: data("1e300"))
            == Keychain.maximumRevision)
    }

    @Test func `an ordinary stamp is unchanged`() {
        #expect(Keychain.revision(from: data("42")) == 42)
        #expect(Keychain.revision(from: nil) == 0)
        #expect(Keychain.revision(from: data("not a number")) == 0)
    }

    /// The next stamp must be strictly greater than every replica, and must stay
    /// finite when one of them is not.
    @Test func `the next stamp advances past a poisoned replica`() {
        let next = Keychain.nextRevisionData([data("inf"), data("7")])

        #expect(Keychain.revision(from: next) == 8)
    }

    @Test func `the next stamp saturates rather than overflowing`() {
        let ceiling = Keychain.maximumRevision
        let next = Keychain.nextRevisionData([data(String(ceiling))])

        #expect(Keychain.revision(from: next) == ceiling)
    }

    @Test func `the first stamp is 1`() {
        #expect(Keychain.revision(from: Keychain.nextRevisionData([nil])) == 1)
    }
}
