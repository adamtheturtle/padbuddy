//
//  coderpadTests+MCPTOMLParsing.swift
//  coderpadTests
//
//  TOML key parsing and declaration-scan coverage for the Codex installer, split
//  from coderpadTests+MCPClientInstall.swift to keep both files under the
//  file-length limit.
//

@testable import CoderPad
import Foundation
import Testing

@Suite("TOML key path parsing (#2537, #2542, #2544)")
struct TOMLKeyPathTests {
    @Test
    func `a dot inside a quoted key does not split the path`() {
        // "my.server" is one key, not two. Splitting it invented declarations that
        // weren't there and hid real ones (#2537).
        #expect(MCPClientInstall.splitTOMLKeyPath("\"my.server\"") == ["my.server"])
        #expect(MCPClientInstall.splitTOMLKeyPath("mcp_servers.\"pad.buddy\"")
            == ["mcp_servers", "pad.buddy"])
        // An unquoted dotted path still splits.
        #expect(MCPClientInstall.splitTOMLKeyPath("mcp_servers.padbuddy") == ["mcp_servers", "padbuddy"])
    }

    @Test
    func `unbalanced quoting is rejected rather than guessed at`() {
        #expect(MCPClientInstall.splitTOMLKeyPath("\"unterminated") == nil)
    }

    @Test
    func `basic-string escapes are interpreted`() {
        // Comparing raw source text let a key be mistaken for a PadBuddy path, or slip
        // past collision detection (#2544).
        #expect(MCPClientInstall.unescapedTOMLKey(#"a\"b"#) == "a\"b")
        #expect(MCPClientInstall.unescapedTOMLKey(#"a\\b"#) == #"a\b"#)
        #expect(MCPClientInstall.unescapedTOMLKey(#"a\tb"#) == "a\tb")
        // An undefined escape is kept verbatim rather than guessed at.
        #expect(MCPClientInstall.unescapedTOMLKey(#"a\qb"#) == #"a\qb"#)
    }

    @Test
    func `a header with trailing junk is not a table`() {
        // Taking the text through the first "]" made a corrupt line a rewrite target,
        // editing a region of a file TOML itself rejects (#2542).
        #expect(MCPClientInstall.tomlHeaderKeyPath("[mcp_servers.padbuddy]") == ["mcp_servers", "padbuddy"])
        #expect(MCPClientInstall.tomlHeaderKeyPath("[mcp_servers.padbuddy]  # note")
            == ["mcp_servers", "padbuddy"])
        #expect(MCPClientInstall.tomlHeaderKeyPath("[mcp_servers.padbuddy] garbage") == nil)
        #expect(MCPClientInstall.tomlHeaderKeyPath("[unclosed") == nil)
    }

    @Test
    func `an array-of-tables header needs both closing brackets`() {
        #expect(MCPClientInstall.tomlHeaderKeyPath("[[mcp_servers.padbuddy]]")
            == ["mcp_servers", "padbuddy"])
        #expect(MCPClientInstall.tomlHeaderKeyPath("[[mcp_servers.padbuddy]") == nil)
    }

    @Test
    func `an equals inside a quoted key does not end the key path`() {
        #expect(MCPClientInstall.tomlKeyValueKeyPath("\"a=b\" = 1") == ["a=b"])
        #expect(MCPClientInstall.tomlKeyValueKeyPath("command = \"/x\"") == ["command"])
        #expect(MCPClientInstall.tomlKeyValueKeyPath("no equals here") == nil)
    }
}

@Suite("Codex declaration scan completeness (#2538, #2539, #2540)")
struct CodexDeclarationScanTests {
    @Test
    func `a lone plain table is replaceable`() {
        let config = """
        [mcp_servers.padbuddy]
        command = "/old/PadBuddy"
        args = ["--mcp"]
        """
        #expect(MCPClientInstall.codexPadbuddyDeclaration(in: config) == .table)
    }

    @Test
    func `a duplicate padbuddy table is refused`() {
        // Returning at the first table called this replaceable, so the rewrite updated
        // one and left the other — Codex still rejects the file (#2539).
        let config = """
        [mcp_servers.padbuddy]
        command = "/a"

        [other]
        x = 1

        [mcp_servers.padbuddy]
        command = "/b"
        """
        #expect(MCPClientInstall.codexPadbuddyDeclaration(in: config) == .other)
    }

    @Test
    func `a later dotted assignment under mcp_servers is refused`() {
        // `padbuddy = ...` inside [mcp_servers] declares the same key as the plain
        // table above it. The scan used to stop at that table and never see this,
        // leaving the conflicting declaration in place after the rewrite (#2540).
        let config = """
        [mcp_servers.padbuddy]
        command = "/a"

        [mcp_servers]
        padbuddy = { command = "/b" }
        """
        #expect(MCPClientInstall.codexPadbuddyDeclaration(in: config) == .other)
    }

    @Test
    func `a root-level dotted assignment is refused`() {
        let config = """
        mcp_servers.padbuddy = { command = "/b" }

        [mcp_servers.padbuddy]
        command = "/a"
        """
        #expect(MCPClientInstall.codexPadbuddyDeclaration(in: config) == .other)
    }

    @Test
    func `a dotted key under an unrelated table is not a conflict`() {
        // Inside [top] this declares top.mcp_servers.padbuddy — a different key
        // entirely, so refusing it would block a perfectly safe install.
        let config = """
        [top]
        mcp_servers.padbuddy = { command = "/b" }
        """
        #expect(MCPClientInstall.codexPadbuddyDeclaration(in: config) == .notDeclared)
    }

    @Test
    func `a later subtable is refused`() {
        let config = """
        [mcp_servers.padbuddy]
        command = "/a"

        [mcp_servers.padbuddy.env]
        TOKEN = "x"
        """
        #expect(MCPClientInstall.codexPadbuddyDeclaration(in: config) == .other)
    }

    @Test
    func `the table's own assignments are not treated as conflicts`() {
        // command/args inside the padbuddy table are what the rewrite replaces, not a
        // competing declaration of the same key.
        let config = """
        [mcp_servers.padbuddy]
        command = "/a"
        args = ["--mcp"]
        """
        #expect(MCPClientInstall.codexPadbuddyDeclaration(in: config) == .table)
    }

    @Test
    func `an unrelated config is not declared`() {
        let config = """
        [mcp_servers.other]
        command = "/x"
        """
        #expect(MCPClientInstall.codexPadbuddyDeclaration(in: config) == .notDeclared)
    }
}

@Suite("Codex table rewrite (#2536, #2543)")
struct CodexTableRewriteTests {
    @Test
    func `custom settings in the padbuddy table survive an update`() {
        // Updating the app path used to discard the whole table body and write back
        // only command and args, silently deleting anything else the user had put
        // there (#2536).
        let body = [
            "[mcp_servers.padbuddy]",
            "command = \"/old/PadBuddy\"",
            "args = [\"--mcp\"]",
            "startup_timeout_ms = 20000",
            "enabled = true"
        ]
        let replacement = MCPClientInstall.codexTableReplacement(body: body, executablePath: "/new/PadBuddy")

        #expect(replacement.contains("command = \"/new/PadBuddy\""))
        #expect(replacement.contains("args = [\"--mcp\"]"))
        #expect(replacement.contains("startup_timeout_ms = 20000"))
        #expect(replacement.contains("enabled = true"))
        // The keys PadBuddy owns appear exactly once, not duplicated alongside the old.
        #expect(replacement.count(where: { $0.hasPrefix("command =") }) == 1)
        #expect(replacement.count(where: { $0.hasPrefix("args =") }) == 1)
        #expect(!replacement.contains { $0.contains("/old/PadBuddy") })
    }

    @Test
    func `a table with nothing but our keys is rewritten to just them`() {
        let body = ["[mcp_servers.padbuddy]", "command = \"/old\"", "args = [\"--mcp\"]"]
        let replacement = MCPClientInstall.codexTableReplacement(body: body, executablePath: "/new")
        #expect(replacement == ["[mcp_servers.padbuddy]", "command = \"/new\"", "args = [\"--mcp\"]"])
    }

    @Test
    func `the file's line-ending convention is detected`() {
        // A CRLF config rewritten with bare LF produces an unrelated whole-file diff
        // and breaks tooling that expects one convention (#2543).
        #expect(MCPClientInstall.dominantLineEnding(of: "a = 1\r\nb = 2\r\n") == "\r\n")
        #expect(MCPClientInstall.dominantLineEnding(of: "a = 1\nb = 2\n") == "\n")
        #expect(MCPClientInstall.dominantLineEnding(of: "") == "\n")
    }
}

@Suite("Codex config structural validation (#2541)")
struct CodexConfigValidationTests {
    @Test
    func `a well-formed config has no structural problem`() {
        let config = """
        # a comment

        [mcp_servers.other]
        command = "/x"
        args = ["--y"]
        env = { A = "1" }
        """
        #expect(MCPClientInstall.codexConfigStructuralProblem(in: config) == nil)
        #expect(MCPClientInstall.codexConfigStructuralProblem(in: "") == nil)
    }

    @Test
    func `a line that is neither header nor setting is reported`() {
        // Appending to a file Codex can't parse reported success while leaving the
        // server just as unavailable (#2541).
        let problem = MCPClientInstall.codexConfigStructuralProblem(in: "[ok]\nthis is not toml\n")
        #expect(problem?.contains("line 2") == true)
    }

    @Test
    func `a malformed table header is reported`() {
        let problem = MCPClientInstall.codexConfigStructuralProblem(in: "[unclosed\n")
        #expect(problem?.contains("line 1") == true)
    }

    @Test
    func `an unterminated multi-line value is reported`() {
        let problem = MCPClientInstall.codexConfigStructuralProblem(in: "x = \"\"\"\nstill going\n")
        #expect(problem?.contains("unclosed") == true)
    }
}
