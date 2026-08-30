//
//  PadBuddyTests+ScreenCampaignSelectionValidity.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Screen campaign selection validity")
struct ScreenCampaignSelectionValidityTests {
    @Test
    func `merged Screen selection resolves its owning account`() {
        let accountID = UUID()

        #expect(ScreenCampaignSelectionValidity.accountID(from: "\(accountID.uuidString):42") == accountID)
        #expect(ScreenCampaignSelectionValidity.accountID(from: nil) == nil)
        #expect(ScreenCampaignSelectionValidity.accountID(from: "not-an-account:42") == nil)
        #expect(ScreenCampaignSelectionValidity.accountID(from: accountID.uuidString) == nil)
    }

    @Test
    func `merged Screen refresh failure revokes only its own selection`() {
        let selectedAccountID = UUID()
        let scopedID = "\(selectedAccountID.uuidString):42"

        #expect(ScreenCampaignSelectionValidity.shouldRevoke(
            scopedID: scopedID,
            failedAccountID: selectedAccountID
        ))
        #expect(!ScreenCampaignSelectionValidity.shouldRevoke(
            scopedID: scopedID,
            failedAccountID: UUID()
        ))
        #expect(!ScreenCampaignSelectionValidity.shouldRevoke(
            scopedID: nil,
            failedAccountID: selectedAccountID
        ))
    }

    @Test func `restored selection waits for its initial account load`() {
        let accountID = UUID()
        let scopedID = "\(accountID.uuidString):42"

        #expect(!ScreenCampaignSelectionValidity.shouldPruneBeforeLoad(
            scopedID: scopedID,
            targetAccountIDs: [accountID],
            invalidatedAccountIDs: []
        ))
        #expect(ScreenCampaignSelectionValidity.shouldPruneBeforeLoad(
            scopedID: scopedID,
            targetAccountIDs: [],
            invalidatedAccountIDs: []
        ))
        #expect(ScreenCampaignSelectionValidity.shouldPruneBeforeLoad(
            scopedID: scopedID,
            targetAccountIDs: [accountID],
            invalidatedAccountIDs: [accountID]
        ))
    }
}

@Suite("Screen campaign selection storage (#4574, #4575)", .serialized)
struct ScreenCampaignSelectionStorageTests {
    @Test func `a non-positive campaign id is not stored`() {
        let account = UUID()
        defer { ScreenCampaignSelectionStore.removeSelection(for: account) }
        ScreenCampaignSelectionStore.save(7, for: account)

        ScreenCampaignSelectionStore.save(0, for: account)

        // It used to "save" and then read back as nil at the next restoration.
        #expect(ScreenCampaignSelectionStore.campaign(for: account) == nil)
    }

    @Test func `a positive campaign id round-trips`() {
        let account = UUID()
        defer { ScreenCampaignSelectionStore.removeSelection(for: account) }

        ScreenCampaignSelectionStore.save(42, for: account)

        #expect(ScreenCampaignSelectionStore.campaign(for: account) == 42)
    }

    @Test func `removing an account clears its selection`() {
        let account = UUID()
        ScreenCampaignSelectionStore.save(42, for: account)

        ScreenCampaignSelectionStore.removeSelection(for: account)

        #expect(ScreenCampaignSelectionStore.campaign(for: account) == nil)
    }

    @Test(arguments: ["", "   ", "not-a-uuid:1", "\(UUID().uuidString)", "\(UUID().uuidString):0",
                      "\(UUID().uuidString):-3", "\(UUID().uuidString):abc"])
    func `an unresolvable merged selection is not a selection`(value: String) {
        #expect(ScreenCampaignSelectionStore.validatedMergedCampaign(value) == nil)

        ScreenCampaignSelectionStore.mergedCampaign = value

        #expect(ScreenCampaignSelectionStore.mergedCampaign == nil)
    }

    @Test func `a scoped merged selection round-trips trimmed`() {
        let scoped = "\(UUID().uuidString):9"
        defer { ScreenCampaignSelectionStore.mergedCampaign = nil }

        ScreenCampaignSelectionStore.mergedCampaign = " \(scoped) "

        #expect(ScreenCampaignSelectionStore.mergedCampaign == scoped)
    }
}
