//
//  coderpadTests+ScreenTestsActionContext.swift
//  coderpadTests
//

@testable import CoderPad
import Foundation
import Testing

@Suite("Screen test action context")
struct ScreenTestsActionContextTests {
    @Test
    func `screen test actions require the same client campaign and account`() throws {
        let account = UUID()
        let identity = try ClientTaskIdentity(
            apiKey: "one",
            baseURL: #require(URL(string: "https://screen.example"))
        )
        let context = ScreenTestsActionContext(clientIdentity: identity, campaignID: 42, accountID: account)

        #expect(context.isCurrent(clientIdentity: identity, campaignID: 42, accountID: account))
        #expect(!context.isCurrent(clientIdentity: identity, campaignID: 43, accountID: account))
        #expect(!context.isCurrent(clientIdentity: identity, campaignID: 42, accountID: UUID()))
        #expect(!context.isCurrent(
            clientIdentity: ClientTaskIdentity(apiKey: "two", baseURL: identity.baseURL),
            campaignID: 42,
            accountID: account
        ))
    }
}
