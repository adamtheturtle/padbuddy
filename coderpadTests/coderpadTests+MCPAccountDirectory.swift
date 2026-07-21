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

    private let uuid = UUID()

    private func singleAccountDirectory() throws -> MCPAccountDirectory {
        let baseURL = try #require(URL(string: "https://example.com"))
        let screenBaseURL = try #require(URL(string: "https://screen.example.com"))
        return MCPAccountDirectory(
            accounts: [
                MCPCredentials(
                    id: "account-a",
                    apiKey: "key",
                    baseURL: baseURL,
                    accountName: "Acme",
                    userEmail: "user@example.com",
                    secondaryApiKey: "screen-key",
                    secondaryBaseURL: screenBaseURL
                )
            ],
            currentID: "account-a"
        )
    }

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
    func `uuid selectors resolve case insensitively`() throws {
        let baseURL = try #require(URL(string: "https://example.com"))
        let directory = MCPAccountDirectory(
            accounts: [
                MCPCredentials(
                    id: uuid.uuidString,
                    apiKey: "key",
                    baseURL: baseURL,
                    accountName: "Primary",
                    userEmail: "user@example.com"
                )
            ],
            currentID: nil
        )

        #expect(directory.resolve(uuid.uuidString.lowercased())?.id == uuid.uuidString)
        #expect(directory.ambiguousAccountIDs(for: uuid.uuidString.lowercased()).isEmpty)
    }

    @Test
    func `list tools reject invalid page before network requests`() async throws {
        let directory = try singleAccountDirectory()
        let outcome = await MCPTools.run(
            name: "list_pads",
            arguments: ["page": 0],
            directory: directory
        )

        #expect(outcome.isError)
        #expect(outcome.text.contains("page"))
    }

    @Test
    func `screen list tests rejects invalid pagination before network requests`() async throws {
        let directory = try singleAccountDirectory()
        let outcome = await MCPTools.run(
            name: "screen_list_tests",
            arguments: ["start": -1, "limit": 0],
            directory: directory
        )

        #expect(outcome.isError)
        #expect(outcome.text.contains("start"))
    }

    @Test
    func `an unavailable stored selection yields no default account (#832)`() {
        // The app's selected account (e.g. Demo, or one with an empty key) was filtered
        // out of the directory; unqualified calls must not fall back to another account.
        let directory = MCPAccountDirectory(
            accounts: duplicateNameDirectory.accounts,
            currentID: "demo-account-not-in-directory"
        )
        #expect(directory.current == nil)
        #expect(directory.currentSelectionUnavailable)
        #expect(directory.resolve(nil) == nil)
        // An explicit selector still works.
        #expect(directory.resolve("account-b")?.id == "account-b")
    }

    @Test
    func `no stored selection still defaults to the first account`() {
        let directory = MCPAccountDirectory(
            accounts: duplicateNameDirectory.accounts,
            currentID: nil
        )
        #expect(directory.current?.id == "account-a")
        #expect(!directory.currentSelectionUnavailable)
    }

    @Test
    func `unqualified tool calls report an unavailable selection instead of retargeting (#832)`() async {
        let directory = MCPAccountDirectory(
            accounts: duplicateNameDirectory.accounts,
            currentID: "demo-account-not-in-directory"
        )
        let outcome = await MCPTools.run(name: "whoami", arguments: [:], directory: directory)

        #expect(outcome.isError)
        #expect(outcome.text.contains("is not available"))
        #expect(outcome.text.contains("Acme"))
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
