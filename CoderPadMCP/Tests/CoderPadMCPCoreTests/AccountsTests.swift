//
//  AccountsTests.swift
//  CoderPadMCPCoreTests
//
//  The multi-account configuration parsing (#521): env fallback, JSON config, name
//  resolution, and the list_accounts directory. Pure, no filesystem.
//

@testable import CoderPadMCPCore
import Foundation
import Testing

@Suite("Account configuration")
struct AccountsTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test
    func `env fallback builds one default account and requires the key`() throws {
        let set = try makeAccountSet(config: nil, environment: [
            "CODERPAD_API_KEY": "k1",
            "CODERPAD_BASE_URL": "https://coderpad.acme.internal"
        ])
        #expect(set.accounts.count == 1)
        #expect(set.defaultAccount.name == "default")
        #expect(set.defaultAccount.apiKey == "k1")
        #expect(set.defaultAccount.baseURL.absoluteString == "https://coderpad.acme.internal")
        #expect(!set.allowWrites)

        #expect(throws: MCPConfigError.noAccounts) {
            try makeAccountSet(config: nil, environment: [:])
        }
    }

    @Test
    func `missing default config falls back to environment`() throws {
        let home = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }

        let config = try loadConfigObject(environment: [:], homeDirectory: home)
        #expect(config == nil)
    }

    @Test
    func `missing explicit config does not fall back to environment`() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appending(path: "missing.json").path

        #expect(throws: MCPConfigLoadError.unreadableConfig(path: path)) {
            _ = try loadConfigObject(environment: ["CODERPAD_MCP_CONFIG": path])
        }
    }

    @Test
    func `malformed explicit config does not fall back to environment`() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "config.json")
        try Data("{".utf8).write(to: url)

        #expect(throws: MCPConfigLoadError.malformedConfig(path: url.path)) {
            _ = try loadConfigObject(environment: [
                "CODERPAD_MCP_CONFIG": url.path,
                "CODERPAD_API_KEY": "env-key"
            ])
        }
    }

    @Test
    func `explicit config must be a JSON object`() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "config.json")
        try Data("[]".utf8).write(to: url)

        #expect(throws: MCPConfigLoadError.nonObjectConfig(path: url.path)) {
            _ = try loadConfigObject(environment: ["CODERPAD_MCP_CONFIG": url.path])
        }
    }

    @Test
    func `explicit config parses an object`() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "config.json")
        try Data(#"{"accounts":[{"name":"Acme","api_key":"key"}]}"#.utf8).write(to: url)

        let config = try #require(try loadConfigObject(environment: ["CODERPAD_MCP_CONFIG": url.path]))
        let accounts = try #require(config["accounts"] as? [[String: Any]])
        #expect(accounts.count == 1)
        #expect(accounts[0]["name"] as? String == "Acme")
    }

    @Test
    func `env writes flag and screen key carry through`() throws {
        let set = try makeAccountSet(config: nil, environment: [
            "CODERPAD_API_KEY": "k1",
            "CODERPAD_MCP_ALLOW_WRITES": "yes",
            "CODERPAD_SCREEN_API_KEY": "s1",
            "CODERPAD_SCREEN_REGION": "EU"
        ])
        #expect(set.allowWrites)
        #expect(set.anyScreenEnabled)
        #expect(set.defaultAccount.screenBaseURL.absoluteString == "https://www.codingame.eu")
    }

    @Test
    func `config accounts parse, pick the marked default, and OR the write flag`() throws {
        let config: [String: Any] = [
            "accounts": [
                ["name": "Acme", "api_key": "a", "base_url": "https://app.coderpad.io"],
                ["name": "Beta", "api_key": "b", "screen_api_key": "sb", "default": true]
            ],
            "allow_writes": true
        ]
        let set = try makeAccountSet(config: config, environment: [:])
        #expect(set.accounts.count == 2)
        #expect(set.defaultAccount.name == "Beta")
        #expect(set.allowWrites)
        #expect(set.anyScreenEnabled)
    }

    @Test
    func `config without a marked default uses the first account`() throws {
        let config: [String: Any] = ["accounts": [
            ["name": "Acme", "api_key": "a"],
            ["name": "Beta", "api_key": "b"]
        ]]
        let set = try makeAccountSet(config: config, environment: [:])
        #expect(set.defaultAccount.name == "Acme")
    }

    @Test
    func `config with multiple marked defaults is rejected`() {
        let config: [String: Any] = ["accounts": [
            ["name": "Acme", "api_key": "a", "default": true],
            ["name": "Beta", "api_key": "b", "default": true]
        ]]

        #expect(throws: MCPConfigError.multipleDefaultAccounts(["Acme", "Beta"])) {
            try makeAccountSet(config: config, environment: [:])
        }
    }

    @Test
    func `resolve matches by name case-insensitively, defaults on nil, nil on unknown`() throws {
        let config: [String: Any] = ["accounts": [
            ["name": "Acme", "api_key": "a", "default": true],
            ["name": "Beta", "api_key": "b"]
        ]]
        let set = try makeAccountSet(config: config, environment: [:])
        #expect(set.resolve(nil)?.name == "Acme")
        #expect(set.resolve("")?.name == "Acme")
        #expect(set.resolve("beta")?.name == "Beta")
        #expect(set.resolve("  BETA ")?.name == "Beta")
        #expect(set.resolve("nope") == nil)
    }

    @Test
    func `missing key and duplicate names are rejected`() {
        #expect(throws: MCPConfigError.missingAPIKey(account: "Acme")) {
            try makeAccountSet(config: ["accounts": [["name": "Acme"]]], environment: [:])
        }
        #expect(throws: MCPConfigError.duplicateName("acme")) {
            try makeAccountSet(config: ["accounts": [
                ["name": "Acme", "api_key": "a"],
                ["name": "acme", "api_key": "b"]
            ]], environment: [:])
        }
    }

    @Test
    func `the list_accounts directory carries names and flags but never keys`() throws {
        let set = try makeAccountSet(config: ["accounts": [
            ["name": "Acme", "api_key": "secret", "default": true],
            ["name": "Beta", "api_key": "secret2", "screen_api_key": "s"]
        ]], environment: [:])
        let directory = set.directory()
        #expect(directory.count == 2)
        let acme = directory[0]
        #expect(acme["name"] as? String == "Acme")
        #expect(acme["is_default"] as? Bool == true)
        #expect(acme["screen_configured"] as? Bool == false)
        #expect(directory[1]["screen_configured"] as? Bool == true)
        // No value anywhere is the API key.
        let flattened = directory.flatMap { $0.values.compactMap { $0 as? String } }
        #expect(!flattened.contains("secret"))
        #expect(!flattened.contains("secret2"))
    }
}
