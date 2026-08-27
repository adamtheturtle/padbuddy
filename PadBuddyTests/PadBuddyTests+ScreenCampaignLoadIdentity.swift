//
//  PadBuddyTests+ScreenCampaignLoadIdentity.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Screen campaign load identity")
struct ScreenCampaignLoadIdentityTests {
    private let first = ClientTaskIdentity(apiKey: "first", baseURL: URL(string: "https://first.example")!)
    private let second = ClientTaskIdentity(apiKey: "second", baseURL: URL(string: "https://second.example")!)

    @Test
    func `only the latest generation for the current client may publish`() {
        #expect(ScreenCampaignsView.isCurrentLoad(
            3, currentGeneration: 3, requestedClientIdentity: first, currentClientIdentity: first
        ))
        #expect(!ScreenCampaignsView.isCurrentLoad(
            2, currentGeneration: 3, requestedClientIdentity: first, currentClientIdentity: first
        ))
        #expect(!ScreenCampaignsView.isCurrentLoad(
            3, currentGeneration: 3, requestedClientIdentity: first, currentClientIdentity: second
        ))
    }
}
