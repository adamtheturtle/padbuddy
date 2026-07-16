//
//  coderpadTests+MCPAccountDirectory.swift
//  coderpadTests
//
//  Tests for in-app MCP account selection safety (#715).
//

@testable import CoderPad
import Foundation
import Testing

@Suite("MCP account directory")
struct MCPAccountDirectoryTests {
    private let duplicateNameDirectory = MCPAccountDirectory(
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
                accountName: "acme",
                userEmail: "b@example.com"
            )
        ],
        currentID: "account-a"
    )

    @Test
    func `duplicate display names do not resolve by name`() {
        #expect(duplicateNameDirectory.resolve("Acme") == nil)
        #expect(duplicateNameDirectory.ambiguousAccountIDs(for: "Acme") == ["account-a", "account-b"])
    }

    @Test
    func `duplicate display names still resolve by id`() {
        #expect(duplicateNameDirectory.resolve("account-b")?.id == "account-b")
        #expect(duplicateNameDirectory.ambiguousAccountIDs(for: "account-b").isEmpty)
    }

    @Test
    func `ambiguous account tool calls list matching ids`() async {
        let outcome = await MCPTools.run(
            name: "whoami",
            arguments: [MCPTools.account: "Acme"],
            directory: duplicateNameDirectory
        )

        #expect(outcome.isError)
        #expect(outcome.text.contains("matches multiple accounts"))
        #expect(outcome.text.contains("account-a"))
        #expect(outcome.text.contains("account-b"))
    }
}
