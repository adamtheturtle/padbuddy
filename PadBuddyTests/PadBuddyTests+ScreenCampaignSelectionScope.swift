//
//  PadBuddyTests+ScreenCampaignSelectionScope.swift
//  PadBuddyTests
//

@testable import PadBuddy
import Foundation
import Testing

@Suite("Screen campaign selection scope")
struct ScreenCampaignSelectionScopeTests {
    @Test
    func `campaign selection restores only for its owning account`() {
        let navigation = WindowNavigation()
        let owner = UUID()
        let other = UUID()
        let campaign = ScreenCampaign(id: 7, name: "Backend")

        navigation.publishScreenCampaign(campaign, accountID: owner)

        #expect(navigation.screenCampaign(for: owner) == campaign)
        #expect(navigation.screenCampaign(for: other) == nil)
        navigation.publishScreenCampaign(nil, accountID: nil)
        #expect(navigation.screenCampaignAccountID == nil)
    }
}
