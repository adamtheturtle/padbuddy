//
//  coderpadTests+CloudSync.swift
//  coderpadTests
//
//  Tests for the iCloud-sync foundation (#536): the stable cross-device account
//  identity and the pure merge helpers that move per-account collections between
//  their local (UUID-keyed) and cloud (sync-id-keyed) forms. The iCloud I/O itself
//  (`CloudSyncStore`) needs the entitlement + a second device, so it's verified
//  separately; the logic that decides what syncs is exercised here.
//

@testable import CoderPad
import Foundation
import Testing

@Suite("iCloud sync foundation")
struct CloudSyncTests {
    private func account(email: String, baseURL: String? = nil, id: UUID = UUID()) -> Account {
        Account(name: "Acme", apiKey: "key", id: id, userEmail: email, baseURL: baseURL)
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

        #expect(jane.syncID != bob.syncID)
        #expect(jane.syncID != janeSelfHosted.syncID)
    }

    @Test
    func `an account with no owner email has an empty sync id`() {
        #expect(account(email: "").syncID.isEmpty)
        #expect(account(email: "   ").syncID.isEmpty)
    }

    @Test
    func `projecting to cloud keys by sync id and drops accounts with no stable id`() {
        let live = UUID()
        let draft = UUID()
        let identities = [live: "host|jane@acme.com", draft: ""]

        let cloud = AccountSyncMerge.toCloud([live: ["pad-1", "pad-2"], draft: ["pad-x"]]) {
            identities[$0]
        }

        #expect(cloud == ["host|jane@acme.com": ["pad-1", "pad-2"]])
    }

    @Test
    func `merging unions cloud favourites into local without losing or deleting any`() {
        let local = UUID()
        let identity = "host|jane@acme.com"

        let merged = AccountSyncMerge.mergeArrays(
            cloud: [identity: ["pad-2", "pad-3"]],
            into: [local: ["pad-1", "pad-2"]]
        ) { $0 == identity ? local : nil }

        // Local order preserved, the cloud-only "pad-3" appended, "pad-2" not doubled,
        // and the local-only "pad-1" untouched (deletions don't propagate in v1).
        #expect(merged[local] == ["pad-1", "pad-2", "pad-3"])
    }

    @Test
    func `merging adopts cloud favourites for an account that is empty locally`() {
        let local = UUID()
        let identity = "host|jane@acme.com"

        let merged = AccountSyncMerge.mergeArrays(
            cloud: [identity: ["pad-9"]],
            into: [:]
        ) { $0 == identity ? local : nil }

        #expect(merged[local] == ["pad-9"])
    }

    @Test
    func `merging ignores cloud entries for accounts not configured on this device`() {
        let local = UUID()

        let merged = AccountSyncMerge.mergeArrays(
            cloud: ["host|someone-else@acme.com": ["pad-7"]],
            into: [local: ["pad-1"]]
        ) { _ in nil }

        #expect(merged == [local: ["pad-1"]])
    }
}
