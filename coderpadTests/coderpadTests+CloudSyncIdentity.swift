//
//  coderpadTests+CloudSyncIdentity.swift
//  coderpadTests
//
//  Tests for `Account.syncID`, the stable cross-device identity that keys every
//  iCloud-synced blob (#536). Split out of `coderpadTests+CloudSync.swift`, which
//  covers the merge helpers, to keep both files under the file-length limit.
//

@testable import CoderPad
import Foundation
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
    func `rotating the API key keeps the sync id`() {
        // The id used to fold in a fingerprint of the key, so every rotation minted a
        // fresh identity and stranded the account's favorites, open-history and
        // preferences under the old one (#2141).
        let before = account(email: "jane@acme.com", apiKey: "old-key")
        let after = account(email: "jane@acme.com", apiKey: "new-key")

        #expect(before.syncID == after.syncID)
        #expect(!before.syncID.contains("old-key"))
    }

    @Test
    func `an account adopts its own legacy fingerprint-bearing id`() {
        let jane = account(email: "jane@acme.com")
        let legacy = "\(jane.syncID)|\(Self.fingerprint)"

        #expect(jane.matchesSyncID(jane.syncID))
        #expect(jane.matchesSyncID(legacy))
        // Another owner's legacy id is still another owner's.
        #expect(!account(email: "bob@acme.com").matchesSyncID(legacy))
    }

    @Test
    func `only a fingerprint-shaped trailing component is adopted`() {
        // Anything else after the identity is an unrelated key space, and adopting it
        // would merge two accounts' cloud data (#2141).
        let jane = account(email: "jane@acme.com")

        #expect(!jane.matchesSyncID("\(jane.syncID)|"))
        #expect(!jane.matchesSyncID("\(jane.syncID)|abc"))
        #expect(!jane.matchesSyncID("\(jane.syncID)|\(Self.fingerprint)|\(Self.fingerprint)"))
        #expect(!jane.matchesSyncID("\(jane.syncID)|zzzzzzzzzzzzzzzzzzzzzzzz"))
        #expect(!jane.matchesSyncID(""))
    }

    @Test
    func `a draft with no identity adopts nothing`() {
        let draft = account(email: "")

        #expect(!draft.matchesSyncID(""))
        #expect(!draft.matchesSyncID("|\(Self.fingerprint)"))
    }

    @Test
    func `a legacy-keyed blob resolves to its account, but an exact match wins`() {
        let jane = account(email: "jane@acme.com")
        let bob = account(email: "bob@acme.com")
        let legacy = "\(jane.syncID)|\(Self.fingerprint)"

        #expect([bob, jane].firstMatchingSyncID(legacy)?.id == jane.id)
        #expect([bob, jane].firstMatchingSyncID(jane.syncID)?.id == jane.id)
        // A record whose *current* id is the one stored beats another record that
        // merely answers to it as a legacy id.
        let impostor = account(email: "jane@acme.com|\(Self.fingerprint)")
        #expect([jane, impostor].firstMatchingSyncID(impostor.syncID)?.id == impostor.id)
        #expect([bob].firstMatchingSyncID(legacy) == nil)
        #expect([bob, jane].firstMatchingSyncID("") == nil)
    }

    @Test
    func `a removed account's legacy keys are dropped from a mirrored blob`() {
        let jane = account(email: "jane@acme.com")
        let bob = account(email: "bob@acme.com")
        var blob = [jane.syncID: 1, "\(jane.syncID)|\(Self.fingerprint)": 2, bob.syncID: 3]

        #expect(CloudSyncIdentity.removeIdentities(matching: jane.syncID, from: &blob))
        #expect(blob == [bob.syncID: 3])
        #expect(!CloudSyncIdentity.removeIdentities(matching: jane.syncID, from: &blob))
    }

    /// A stand-in for the truncated SHA-256 the pre-#2141 ids carried: only its
    /// shape — `CloudSyncIdentity.fingerprintLength` hex characters — is matched.
    private static let fingerprint = String(repeating: "ab", count: CloudSyncIdentity.fingerprintLength / 2)

    @Test
    func `an account with no owner email has an empty sync id`() {
        #expect(account(email: "").syncID.isEmpty)
        #expect(account(email: "   ").syncID.isEmpty)
        #expect(account(email: "jane@acme.com", apiKey: "   ").syncID.isEmpty)
    }
}
