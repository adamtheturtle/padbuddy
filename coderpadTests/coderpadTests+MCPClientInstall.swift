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
    }

#endif
