//
//  coderpadTests+MCPClientInstall.swift
//  coderpadTests
//
//  TOML handling in the Codex one-click installer (#812, #813, #815): escaping the
//  executable path, recognizing every declaration form of mcp_servers.padbuddy, and
//  rewriting only the plain table form.
//

@testable import CoderPad
import Foundation
import Testing

#if os(macOS)

    @Suite("JSON MCP install")
    struct MCPClientInstallJSONTests {
        @Test
        func `adding padbuddy preserves existing JSON servers`() throws {
            let root: [String: Any] = [
                "mcpServers": [
                    "other": ["command": "/bin/other"]
                ],
                "otherSetting": true
            ]

            let merged = try MCPClientInstall.jsonConfigByAddingServer(
                to: root,
                executablePath: "/Applications/PadBuddy"
            )
            let servers = try #require(merged.root["mcpServers"] as? [String: Any])
            let padbuddy = try #require(servers["padbuddy"] as? [String: Any])

            #expect(merged.alreadyPresent == false)
            #expect(servers["other"] != nil)
            #expect(padbuddy["command"] as? String == "/Applications/PadBuddy")
            #expect(padbuddy["args"] as? [String] == ["--mcp"])
            #expect(merged.root["otherSetting"] as? Bool == true)
        }

        @Test
        func `wrong typed mcpServers is rejected without replacement`() {
            let root: [String: Any] = [
                "mcpServers": ["existing-value"],
                "otherSetting": true
            ]

            #expect(throws: MCPClientInstall.JSONConfigError.self) {
                try MCPClientInstall.jsonConfigByAddingServer(to: root, executablePath: "/Applications/PadBuddy")
            }
        }
    }

    @Suite("Codex TOML install")
    struct MCPClientInstallTOMLTests {
        // MARK: - tomlBasicString (#813)

        @Test
        func `plain path is quoted unchanged`() {
            #expect(MCPClientInstall.tomlBasicString("/Applications/PadBuddy.app/Contents/MacOS/PadBuddy")
                == "\"/Applications/PadBuddy.app/Contents/MacOS/PadBuddy\"")
        }

        @Test
        func `quotes and backslashes are escaped`() {
            #expect(MCPClientInstall.tomlBasicString(#"/tmp/a"b\c"#) == #""/tmp/a\"b\\c""#)
        }

        @Test
        func `control characters are escaped`() {
            #expect(MCPClientInstall.tomlBasicString("/tmp/a\nb\tc") == #""/tmp/a\nb\tc""#)
            #expect(MCPClientInstall.tomlBasicString("/tmp/a\u{01}b") == "\"/tmp/a\\u0001b\"")
        }

        @Test
        func `server block embeds the escaped path`() {
            let block = MCPClientInstall.codexServerBlock(executablePath: #"/tmp/we"ird/PadBuddy"#)
            #expect(block.contains(#"command = "/tmp/we\"ird/PadBuddy""#))
            #expect(block.hasPrefix("[mcp_servers.padbuddy]\n"))
        }

        // MARK: - codexPadbuddyDeclaration (#815)

        @Test
        func `empty and unrelated configs have no declaration`() {
            #expect(MCPClientInstall.codexPadbuddyDeclaration(in: "") == .notDeclared)
            let unrelated = """
            [mcp_servers.other]
            command = "/bin/other"
            """
            #expect(MCPClientInstall.codexPadbuddyDeclaration(in: unrelated) == .notDeclared)
        }

        @Test
        func `plain table header is replaceable`() {
            let toml = """
            [mcp_servers.padbuddy]
            command = "/old/PadBuddy"
            """
            #expect(MCPClientInstall.codexPadbuddyDeclaration(in: toml) == .table)
        }

        @Test
        func `quoted and spaced headers are recognized`() {
            #expect(MCPClientInstall.codexPadbuddyDeclaration(in: "[mcp_servers.\"padbuddy\"]") == .table)
            #expect(MCPClientInstall.codexPadbuddyDeclaration(in: "[mcp_servers.'padbuddy']") == .table)
            #expect(MCPClientInstall.codexPadbuddyDeclaration(in: "[ mcp_servers . padbuddy ]") == .table)
        }

        @Test
        func `dotted key declaration is detected but not replaceable`() {
            let toml = "mcp_servers.padbuddy = { command = \"/old/PadBuddy\" }"
            #expect(MCPClientInstall.codexPadbuddyDeclaration(in: toml) == .other)
        }

        @Test
        func `inline key under mcp_servers table is detected but not replaceable`() {
            let toml = """
            [mcp_servers]
            padbuddy = { command = "/old/PadBuddy" }
            """
            #expect(MCPClientInstall.codexPadbuddyDeclaration(in: toml) == .other)
        }

        @Test
        func `array of tables is detected but not replaceable`() {
            #expect(MCPClientInstall.codexPadbuddyDeclaration(in: "[[mcp_servers.padbuddy]]") == .other)
        }

        @Test
        func `same key name under a different table is ignored`() {
            let toml = """
            [profiles]
            padbuddy = "something"
            """
            #expect(MCPClientInstall.codexPadbuddyDeclaration(in: toml) == .notDeclared)
        }

        // MARK: - replacingCodexServer

        @Test
        func `replacement preserves surrounding tables`() {
            let existing = """
            [model]
            name = "gpt"

            [mcp_servers.padbuddy]
            command = "/old/PadBuddy"
            args = ["--mcp"]

            [mcp_servers.other]
            command = "/bin/other"
            """
            let block = MCPClientInstall.codexServerBlock(executablePath: "/new/PadBuddy")
            let updated = MCPClientInstall.replacingCodexServer(in: existing, with: block)
            #expect(updated.contains("command = \"/new/PadBuddy\""))
            #expect(!updated.contains("/old/PadBuddy"))
            #expect(updated.contains("[model]"))
            #expect(updated.contains("[mcp_servers.other]"))
            #expect(MCPClientInstall.codexPadbuddyDeclaration(in: updated) == .table)
        }

        @Test
        func `replacement matches quoted header form`() {
            let existing = """
            [mcp_servers."padbuddy"]
            command = "/old/PadBuddy"
            """
            let block = MCPClientInstall.codexServerBlock(executablePath: "/new/PadBuddy")
            let updated = MCPClientInstall.replacingCodexServer(in: existing, with: block)
            #expect(updated.contains("command = \"/new/PadBuddy\""))
            #expect(!updated.contains("/old/PadBuddy"))
        }

        // MARK: - Multi-line arrays and strings (#1037)

        @Test
        func `replacement removes a padbuddy table containing a multi-line array whole`() {
            let existing = """
            [mcp_servers.padbuddy]
            command = "/old/PadBuddy"
            matrix = [
            [1, 2],
            [3, 4]
            ]

            [mcp_servers.other]
            command = "/bin/other"
            """
            let block = MCPClientInstall.codexServerBlock(executablePath: "/new/PadBuddy")
            let updated = MCPClientInstall.replacingCodexServer(in: existing, with: block)
            #expect(updated.contains("command = \"/new/PadBuddy\""))
            #expect(!updated.contains("/old/PadBuddy"))
            #expect(!updated.contains("[1, 2]"))
            #expect(!updated.contains("[3, 4]"))
            #expect(updated.contains("[mcp_servers.other]"))
            #expect(MCPClientInstall.codexPadbuddyDeclaration(in: updated) == .table)
        }

        @Test
        func `a header-looking line inside a multi-line string is not a declaration`() {
            let toml = """
            [mcp_servers.other]
            notes = \"\"\"
            [mcp_servers.padbuddy]
            command = "/fake"
            \"\"\"
            """
            #expect(MCPClientInstall.codexPadbuddyDeclaration(in: toml) == .notDeclared)

            let literal = """
            [mcp_servers.other]
            notes = '''
            [mcp_servers.padbuddy]
            '''
            """
            #expect(MCPClientInstall.codexPadbuddyDeclaration(in: literal) == .notDeclared)
        }

        @Test
        func `a header-looking line inside a multi-line array is not a declaration`() {
            let toml = """
            [profiles]
            matrix = [
            "[mcp_servers.padbuddy]",
            2,
            ]
            """
            #expect(MCPClientInstall.codexPadbuddyDeclaration(in: toml) == .notDeclared)
        }

        @Test
        func `a real padbuddy table after a multi-line construct is still found`() {
            let toml = """
            [profiles]
            matrix = [
            1,
            2,
            ]

            [mcp_servers.padbuddy]
            command = "/old/PadBuddy"
            """
            #expect(MCPClientInstall.codexPadbuddyDeclaration(in: toml) == .table)

            let block = MCPClientInstall.codexServerBlock(executablePath: "/new/PadBuddy")
            let updated = MCPClientInstall.replacingCodexServer(in: toml, with: block)
            #expect(updated.contains("command = \"/new/PadBuddy\""))
            #expect(!updated.contains("/old/PadBuddy"))
            #expect(updated.contains("matrix = ["))
        }

        @Test
        func `escapes and comments do not derail the multi-line scanner`() {
            // An escaped quote inside a basic string, a comment containing brackets, and a
            // single-line pair of strings must all leave the scanner balanced.
            let toml = """
            [profiles]
            note = "an \\" escaped quote"
            other = 'literal [ bracket'
            # a comment with [ and " and '''
            [mcp_servers.padbuddy]
            command = "/old/PadBuddy"
            """
            #expect(MCPClientInstall.codexPadbuddyDeclaration(in: toml) == .table)
        }
    }

#endif

@Suite("MCP config write safety (#2531, #2533, #2534, #2535)")
struct MCPConfigWriteSafetyTests {
    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-write-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test
    func `rewriting a config preserves its permissions and leaves a backup`() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = directory.appendingPathComponent("config.toml")
        try Data("original = true\n".utf8).write(to: config)
        // A deliberately restricted config must not come back world-readable.
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: config.path)

        try MCPClientInstall.writeConfig(Data("updated = true\n".utf8), to: config)

        let attributes = try FileManager.default.attributesOfItem(atPath: config.path)
        let mode = try #require(attributes[.posixPermissions] as? Int)
        #expect(mode == 0o600)
        #expect(try String(contentsOf: config, encoding: .utf8) == "updated = true\n")

        // The previous contents stay recoverable beside the file (#2535).
        let backup = directory.appendingPathComponent("config.toml" + MCPClientInstall.backupSuffix)
        #expect(try String(contentsOf: backup, encoding: .utf8) == "original = true\n")
    }

    @Test
    func `writing a new config needs no backup`() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = directory.appendingPathComponent("mcp.json")

        try MCPClientInstall.writeConfig(Data("{}".utf8), to: config)

        #expect(try String(contentsOf: config, encoding: .utf8) == "{}")
        let backup = directory.appendingPathComponent("mcp.json" + MCPClientInstall.backupSuffix)
        #expect(!FileManager.default.fileExists(atPath: backup.path))
    }

    @Test
    func `only a runnable file counts as an executable`() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(!MCPClientInstall.isRunnableExecutable(""))
        #expect(!MCPClientInstall.isRunnableExecutable(directory.appendingPathComponent("gone").path))
        // A directory is not a command, even though it exists and is "executable".
        #expect(!MCPClientInstall.isRunnableExecutable(directory.path))

        let script = directory.appendingPathComponent("padbuddy")
        try Data("#!/bin/sh\n".utf8).write(to: script)
        #expect(!MCPClientInstall.isRunnableExecutable(script.path))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        #expect(MCPClientInstall.isRunnableExecutable(script.path))
    }
}
