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
    func `different API keys for the same owner and endpoint get different sync ids`() {
        let orgA = account(email: "jane@acme.com", apiKey: "org-a-key")
        let orgB = account(email: "jane@acme.com", apiKey: "org-b-key")

        #expect(orgA.syncID != orgB.syncID)
    }

    @Test
    func `an account with no owner email has an empty sync id`() {
        #expect(account(email: "").syncID.isEmpty)
        #expect(account(email: "   ").syncID.isEmpty)
        #expect(account(email: "jane@acme.com", apiKey: "   ").syncID.isEmpty)
    }
}
