//
//  coderpadTests+ScreenTestsLoadIdentity.swift
//  coderpadTests
//

@testable import CoderPad
import Foundation
import Testing

@Suite("Screen tests load identity")
struct ScreenTestsLoadIdentityTests {
    private let first = ClientTaskIdentity(apiKey: "first", baseURL: URL(string: "https://first.example")!)
    private let second = ClientTaskIdentity(apiKey: "second", baseURL: URL(string: "https://second.example")!)

    @Test
    func `task identity includes both client and campaign`() {
        let original = ScreenTestsLoadIdentity(clientIdentity: first, campaignID: 7)

        #expect(original != ScreenTestsLoadIdentity(clientIdentity: second, campaignID: 7))
        #expect(original != ScreenTestsLoadIdentity(clientIdentity: first, campaignID: 8))
    }

    @Test
    func `only current generation and client may publish`() {
        #expect(ScreenTestsLoadIdentity.isCurrent(
            4, currentGeneration: 4, requestedClientIdentity: first, currentClientIdentity: first
        ))
        #expect(!ScreenTestsLoadIdentity.isCurrent(
            3, currentGeneration: 4, requestedClientIdentity: first, currentClientIdentity: first
        ))
        #expect(!ScreenTestsLoadIdentity.isCurrent(
            4, currentGeneration: 4, requestedClientIdentity: first, currentClientIdentity: second
        ))
    }
}
