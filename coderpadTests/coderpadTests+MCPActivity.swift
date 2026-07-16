//
//  coderpadTests+MCPActivity.swift
//  coderpadTests
//
//  Tests for the in-app MCP activity attribution (#716): failed calls with an
//  invalid explicit account selector must not be attributed to the default account.
//

@testable import CoderPad
import Foundation
import Testing

@Suite("MCP activity attribution")
struct MCPActivityAttributionTests {
    private let directory = MCPAccountDirectory(
        accounts: [
            MCPCredentials(
                id: "account-a",
                apiKey: "key-a",
                baseURL: URL(string: "https://example.com")!,
                accountName: "Acme",
                userEmail: "a@example.com"
            ),
            MCPCredentials(
                id: "account-b",
                apiKey: "key-b",
                baseURL: URL(string: "https://example.com")!,
                accountName: "Beta",
                userEmail: "b@example.com"
            )
        ],
        currentID: "account-a"
    )

    @Test
    func `omitted and empty account selectors use the default account`() {
        #expect(MCPActivityAttribution.accountName(arguments: [:], directory: directory) == "Acme")
        #expect(MCPActivityAttribution.accountName(arguments: [MCPTools.account: "  "], directory: directory) == "Acme")
    }

    @Test
    func `valid explicit selectors use the matched account`() {
        #expect(MCPActivityAttribution.accountName(arguments: [MCPTools.account: "beta"], directory: directory) == "Beta")
        #expect(MCPActivityAttribution.accountName(arguments: [MCPTools.account: "account-b"], directory: directory) == "Beta")
    }

    @Test
    func `invalid explicit selector is logged as requested`() {
        #expect(
            MCPActivityAttribution.accountName(arguments: [MCPTools.account: "does-not-exist"], directory: directory)
                == "does-not-exist"
        )
    }
}
