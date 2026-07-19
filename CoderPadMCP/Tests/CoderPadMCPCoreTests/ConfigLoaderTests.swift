//
//  ConfigLoaderTests.swift
//  CoderPadMCPCoreTests
//

@testable import CoderPadMCPCore
import Foundation
import Testing

@Suite("Config file loading")
struct ConfigLoaderTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString,
                                                                   directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test
    func `missing default config falls back to environment`() throws {
        let home = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(try loadConfigObject(environment: [:], homeDirectory: home) == nil)
    }

    @Test
    func `missing explicit config does not fall back to environment`() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appending(path: "missing.json").path
        #expect(throws: MCPConfigLoadError.missingConfig(path: path)) {
            _ = try loadConfigObject(environment: ["CODERPAD_MCP_CONFIG": path])
        }
    }

    @Test
    func `explicit config directory is reported separately from a read failure`() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(throws: MCPConfigLoadError.notRegularFile(path: directory.path)) {
            _ = try loadConfigObject(environment: ["CODERPAD_MCP_CONFIG": directory.path])
        }
    }

    @Test
    func `filesystem errors retain safe remediation categories`() {
        let path = "/private/config.json"
        #expect(classifiedConfigReadError(path: path, error: CocoaError(.fileReadNoSuchFile))
            == .missingConfig(path: path))
        #expect(classifiedConfigReadError(path: path, error: CocoaError(.fileReadNoPermission))
            == .permissionDenied(path: path))
        #expect(classifiedConfigReadError(path: path, error: CocoaError(.fileReadUnknown))
            == .readFailed(path: path))
    }

    @Test
    func `malformed explicit config does not fall back to environment`() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "config.json")
        try Data("{".utf8).write(to: url)
        #expect(throws: MCPConfigLoadError.malformedConfig(path: url.path)) {
            _ = try loadConfigObject(environment: ["CODERPAD_MCP_CONFIG": url.path])
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
}
