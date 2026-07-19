//
//  coderpadTests+OrganizationReloadIdentity.swift
//  coderpadTests
//

@testable import CoderPad
import Foundation
import Testing

extension coderpadTests {
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
    }
}
