//
//  coderpadTests+ScreenCampaignSelectionValidity.swift
//  coderpadTests
//

@testable import CoderPad
import Foundation
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
}
