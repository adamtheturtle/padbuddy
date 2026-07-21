//
//  coderpadTests+MCPConfigVerification.swift
//  coderpadTests
//

#if os(macOS)
    @testable import CoderPad
    import Foundation
    import Testing

    @Suite("MCP config post-write verification")
    struct MCPConfigVerificationTests {
        private let executable = "/Applications/PadBuddy.app/Contents/MacOS/PadBuddy"

        @Test
        func `written JSON is verified for the expected server shape`() throws {
            let (directory, config) = try temporaryConfig(named: "mcp.json")
            defer { try? FileManager.default.removeItem(at: directory) }
            let valid = #"{"mcpServers":{"padbuddy":{"command":"\#(executable)","args":["--mcp"]}}}"#
            try Data(valid.utf8).write(to: config)

            try MCPClientInstall.verifyJSONConfig(at: config, executablePath: executable)
            try Data(#"{"mcpServers":{"padbuddy":{"command":"wrong"}}}"#.utf8).write(to: config)
            #expect(throws: MCPClientInstall.ConfigVerificationError.self) {
                try MCPClientInstall.verifyJSONConfig(at: config, executablePath: executable)
            }
        }

        @Test
        func `written TOML is verified for the expected server shape`() throws {
            let (directory, config) = try temporaryConfig(named: "config.toml")
            defer { try? FileManager.default.removeItem(at: directory) }
            try Data(MCPClientInstall.codexServerBlock(executablePath: executable).utf8).write(to: config)

            try MCPClientInstall.verifyCodexConfig(at: config, executablePath: executable)
            try Data("[mcp_servers.padbuddy]\ncommand = \"wrong\"\n".utf8).write(to: config)
            #expect(throws: MCPClientInstall.ConfigVerificationError.self) {
                try MCPClientInstall.verifyCodexConfig(at: config, executablePath: executable)
            }
        }

        @Test
        func `verification failure identifies the available backup`() throws {
            let (directory, config) = try temporaryConfig(named: "mcp.json")
            defer { try? FileManager.default.removeItem(at: directory) }
            let backup = URL(fileURLWithPath: config.path + MCPClientInstall.backupSuffix)
            try Data("previous".utf8).write(to: backup)

            let message = MCPClientInstall.verificationRecoveryMessage(
                problem: "Verification failed.", url: config
            )

            #expect(message.contains(backup.path))
            #expect(message.contains("Restore"))
        }

        @Test
        func `first install verification failure tells the user to remove and retry`() throws {
            let (directory, config) = try temporaryConfig(named: "mcp.json")
            defer { try? FileManager.default.removeItem(at: directory) }

            let message = MCPClientInstall.verificationRecoveryMessage(
                problem: "Verification failed.", url: config
            )

            #expect(message.contains(config.path))
            #expect(message.contains("Remove"))
            #expect(message.contains("try again"))
        }

        private func temporaryConfig(named name: String) throws -> (URL, URL) {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("mcp-verify-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return (directory, directory.appendingPathComponent(name))
        }
    }
#endif
