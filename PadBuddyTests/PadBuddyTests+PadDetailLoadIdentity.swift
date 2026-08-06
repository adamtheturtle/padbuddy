//
//  PadBuddyTests+PadDetailLoadIdentity.swift
//  PadBuddyTests
//

@testable import PadBuddy
import Foundation
import Testing

@Suite("Pad detail load identity (#1333)")
struct PadDetailLoadIdentityTests {
    @Test
    func `only the latest matching pad account and client may publish`() throws {
        let account = UUID()
        let firstClient = try ClientTaskIdentity(
            apiKey: "first", baseURL: #require(URL(string: "https://first.example"))
        )
        let secondClient = try ClientTaskIdentity(
            apiKey: "second", baseURL: #require(URL(string: "https://second.example"))
        )
        let requested = PadDetailLoadIdentity(padID: "pad", accountID: account, clientIdentity: firstClient)

        #expect(PadDetailLoadIdentity.isCurrent(
            generation: 3, currentGeneration: 3, requested: requested, current: requested
        ))
        #expect(!PadDetailLoadIdentity.isCurrent(
            generation: 2, currentGeneration: 3, requested: requested, current: requested
        ))
        #expect(!PadDetailLoadIdentity.isCurrent(
            generation: 3, currentGeneration: 3, requested: requested,
            current: PadDetailLoadIdentity(padID: "other", accountID: account, clientIdentity: firstClient)
        ))
        #expect(!PadDetailLoadIdentity.isCurrent(
            generation: 3, currentGeneration: 3, requested: requested,
            current: PadDetailLoadIdentity(padID: "pad", accountID: UUID(), clientIdentity: firstClient)
        ))
        #expect(!PadDetailLoadIdentity.isCurrent(
            generation: 3, currentGeneration: 3, requested: requested,
            current: PadDetailLoadIdentity(padID: "pad", accountID: account, clientIdentity: secondClient)
        ))
        #expect(!PadDetailLoadIdentity.isCurrent(
            generation: 3, currentGeneration: 3, requested: requested, current: requested, isCancelled: true
        ))
    }
}
