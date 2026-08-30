//
//  PadBuddyTests+ScreenWebhookContext.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Screen webhook context")
@MainActor
struct ScreenWebhookContextTests {
    @Test
    func `account and full client identity must both remain current`() throws {
        let account = UUID()
        let identity = try ClientTaskIdentity(apiKey: "first", baseURL: #require(URL(string: "https://first.example")))
        let context = ScreenWebhookContext(accountID: account, clientIdentity: identity)

        #expect(context.matches(accountID: account, clientIdentity: identity))
        #expect(!context.matches(accountID: UUID(), clientIdentity: identity))
        #expect(!context.matches(
            accountID: account,
            clientIdentity: ClientTaskIdentity(apiKey: "second", baseURL: identity.baseURL)
        ))
    }

    @Test
    func `sheet teardown cancels only before a webhook mutation is issued`() {
        #expect(ScreenWebhookMutationLifetime.shouldCancelOnDisappear(mutationWasIssued: false))
        #expect(!ScreenWebhookMutationLifetime.shouldCancelOnDisappear(mutationWasIssued: true))
    }

    @Test func `only the newest webhook load context may finish loading`() throws {
        let account = UUID()
        let firstIdentity = try ClientTaskIdentity(
            apiKey: "first", baseURL: #require(URL(string: "https://example.com"))
        )
        let secondIdentity = ClientTaskIdentity(
            apiKey: "second", baseURL: firstIdentity.baseURL
        )
        let first = ScreenWebhookContext(
            accountID: account,
            clientIdentity: firstIdentity
        )
        let second = ScreenWebhookContext(
            accountID: account,
            clientIdentity: secondIdentity
        )

        #expect(ScreenWebhookLoadIdentity.isCurrent(
            2, currentGeneration: 2, requestedContext: second, currentContext: second
        ))
        #expect(!ScreenWebhookLoadIdentity.isCurrent(
            1, currentGeneration: 2, requestedContext: first, currentContext: second
        ))
    }
}
