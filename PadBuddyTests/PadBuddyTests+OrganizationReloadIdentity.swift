//
//  PadBuddyTests+OrganizationReloadIdentity.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Organization reload identity")
struct OrganizationReloadIdentityTests {
    @Test
    func `organization reload requires latest generation and owner`() throws {
        let accountID = UUID()
        let firstOwner = try OrganizationStatsOwner(
            accountID: accountID,
            clientIdentity: ClientTaskIdentity(
                apiKey: "first",
                baseURL: #require(URL(string: "https://first.example"))
            )
        )
        let secondOwner = try OrganizationStatsOwner(
            accountID: accountID,
            clientIdentity: ClientTaskIdentity(
                apiKey: "second",
                baseURL: #require(URL(string: "https://second.example"))
            )
        )

        #expect(OrganizationReloadIdentity.isCurrent(
            2,
            currentGeneration: 2,
            requestedOwner: firstOwner,
            currentOwner: firstOwner
        ))
        #expect(!OrganizationReloadIdentity.isCurrent(
            1,
            currentGeneration: 2,
            requestedOwner: firstOwner,
            currentOwner: firstOwner
        ))
        #expect(!OrganizationReloadIdentity.isCurrent(
            2,
            currentGeneration: 2,
            requestedOwner: firstOwner,
            currentOwner: secondOwner
        ))

        #expect(OrganizationReloadIdentity.areStatsCurrent(
            statsGeneration: 4,
            currentStatsGeneration: 4
        ))
        #expect(!OrganizationReloadIdentity.areStatsCurrent(
            statsGeneration: 3,
            currentStatsGeneration: 4
        ))
    }
}
