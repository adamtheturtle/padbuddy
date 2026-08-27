//
//  PadBuddyTests+LegacyWidgetMigration.swift
//  PadBuddyTests
//
//  Migration of the pre-mailbox widget handoff files: identity and validation.
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Legacy widget handoff migration identity (#4551)")
struct LegacyWidgetMigrationIdentityTests {
    @Test func `two files claimed under one singleton name get different identities`() {
        let first = "legacy-import-\(UUID().uuidString)-pending-new-pad.json"
        let second = "legacy-import-\(UUID().uuidString)-pending-new-pad.json"

        #expect(WidgetSharedStore.legacyMigrationID(claimedFileName: first)
            != WidgetSharedStore.legacyMigrationID(claimedFileName: second))
    }

    @Test func `a claimed file keeps one identity across retries`() {
        let claimID = UUID()
        let name = "legacy-import-\(claimID.uuidString)-pending-open-pad.json"

        #expect(WidgetSharedStore.legacyMigrationID(claimedFileName: name) == claimID)
    }

    @Test func `an unclaimed name has no claim identity`() {
        #expect(WidgetSharedStore.legacyMigrationID(claimedFileName: "pending-new-pad.json") == nil)
    }
}

@Suite("Legacy widget handoff migration validation (#4553, #4554, #4555)")
struct LegacyWidgetMigrationValidationTests {
    private func encoded(_ value: some Encodable) throws -> Data {
        try JSONEncoder().encode(value)
    }

    @Test func `a well-formed new pad payload migrates`() throws {
        let account = UUID()
        let data = try encoded(WidgetNewPadRequest(account: account.uuidString, question: 7, id: UUID()))

        let request = WidgetSharedStore.validatedLegacyRequest(from: data, isNewPad: true)

        guard case let .newPad(migrated)? = request else {
            Issue.record("A valid payload should migrate")
            return
        }

        #expect(migrated.account == account.uuidString)
        #expect(migrated.question == 7)
    }

    @Test func `a malformed account identifier is rejected`() throws {
        let data = try encoded(WidgetNewPadRequest(account: "not-a-uuid", question: nil, id: UUID()))

        #expect(WidgetSharedStore.validatedLegacyRequest(from: data, isNewPad: true) == nil)
    }

    @Test func `a non-positive question id is rejected`() throws {
        let data = try encoded(
            WidgetNewPadRequest(account: UUID().uuidString, question: 0, id: UUID())
        )

        #expect(WidgetSharedStore.validatedLegacyRequest(from: data, isNewPad: true) == nil)
    }

    @Test func `a seeded question with no account is rejected`() throws {
        let data = try encoded(WidgetNewPadRequest(account: nil, question: 7, id: UUID()))

        #expect(WidgetSharedStore.validatedLegacyRequest(from: data, isNewPad: true) == nil)
    }

    @Test func `an accountless payload with no seed still migrates`() throws {
        let data = try encoded(WidgetNewPadRequest(account: nil, question: nil, id: UUID()))

        #expect(WidgetSharedStore.validatedLegacyRequest(from: data, isNewPad: true) != nil)
    }

    @Test func `a malformed pad id is rejected`() throws {
        let data = try encoded(WidgetOpenPadRequest(id: "../etc/passwd", account: nil))

        #expect(WidgetSharedStore.validatedLegacyRequest(from: data, isNewPad: false) == nil)
    }

    @Test func `an overlong pad id is rejected`() throws {
        let overlong = String(repeating: "a", count: WidgetSharedStore.maxHandoffPadIDLength + 1)
        let data = try encoded(WidgetOpenPadRequest(id: overlong, account: nil))

        #expect(WidgetSharedStore.validatedLegacyRequest(from: data, isNewPad: false) == nil)
    }

    @Test func `a well-formed open pad payload migrates trimmed`() throws {
        let data = try encoded(WidgetOpenPadRequest(id: "  abc-123  ", account: nil))

        guard case let .openPad(migrated)? = WidgetSharedStore.validatedLegacyRequest(
            from: data, isNewPad: false
        ) else {
            Issue.record("A valid payload should migrate")
            return
        }

        #expect(migrated.id == "abc-123")
    }

    @Test func `an undecodable payload is rejected`() {
        #expect(WidgetSharedStore.validatedLegacyRequest(from: Data("not json".utf8), isNewPad: true) == nil)
        // An open-pad payload has a required id, so an empty object is undecodable too.
        #expect(WidgetSharedStore.validatedLegacyRequest(from: Data("{}".utf8), isNewPad: false) == nil)
    }
}
