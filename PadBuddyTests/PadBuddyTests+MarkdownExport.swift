//
//  PadBuddyTests+MarkdownExport.swift
//  PadBuddyTests
//
//  Tests for the pad Markdown export (#524): document structure, inline escaping, code
//  fence sizing, and language normalization. The builder is pure, so it's tested without
//  any UI or network.
//

@testable import PadBuddy
import Foundation
import Testing

@Suite("Pad Markdown export")
struct PadMarkdownExportTests {
    private func padWithParticipants(_ participants: [String]) throws -> Pad {
        let data = try JSONSerialization.data(withJSONObject: [
            "id": "pad-1", "title": "Interview", "owner_email": "owner@example.com",
            "participants": participants
        ])
        return try CoderPadClient.decoder.decode(Pad.self, from: data)
    }

    @Test
    func `pad summaries hide identities by default`() throws {
        let rows = try padSummaryRows(padWithParticipants(["candidate@example.com"]))
        #expect(rows.first(where: { $0.0 == "Owner" })?.1 == "Hidden")
        #expect(rows.first(where: { $0.0 == "Participants" })?.1 == "1 hidden")
        #expect(!rows.map(\.1).joined().contains("example.com"))
    }

    @Test
    func `opted-in pad summaries bound participant identities`() throws {
        let participants = (1 ... 12).map { "person\($0)@example.com" }
        let rows = try padSummaryRows(padWithParticipants(participants), identityPolicy: .include)
        let value = try #require(rows.first(where: { $0.0 == "Participants" })?.1)
        #expect(value.contains("person10@example.com"))
        #expect(!value.contains("person11@example.com"))
        #expect(value.hasSuffix("and 2 more participants"))
    }

    @Test
    func `document has a title, a summary list, and a fenced block per file`() {
        let markdown = padMarkdownDocument(
            title: "Phone Screen",
            summary: [("Type", "Interview"), ("Owner", "Ada")],
            files: [
                PadPrintFile(id: "1", title: "main.py", code: "print('hi')", language: "python"),
                PadPrintFile(id: "2", title: "test.py", code: "assert True", language: "python")
            ],
            sourceURL: URL(string: "https://app.coderpad.io/ABC123"),
            generatedAt: Date(timeIntervalSince1970: 1_721_044_800)
        )
        #expect(markdown.hasPrefix("# Phone Screen\n"))
        #expect(markdown.contains("Generated: 2024-07-15T12:00:00Z"))
        #expect(markdown.contains("Source: <https://app.coderpad.io/ABC123>"))
        #expect(markdown.contains("- **Type:** Interview"))
        #expect(markdown.contains("- **Owner:** Ada"))
        #expect(markdown.contains("## main.py"))
        #expect(markdown.contains("```python\nprint('hi')\n```"))
        #expect(markdown.contains("## test.py"))
        #expect(markdown.hasSuffix("\n"))
    }

    @Test
    func `an empty title falls back to a placeholder`() {
        let markdown = padMarkdownDocument(title: "   ", summary: [], files: [])
        #expect(markdown.hasPrefix("# Untitled Pad"))
    }

    @Test
    func `no summary rows produce no bullet list`() {
        let markdown = padMarkdownDocument(
            title: "T", summary: [],
            files: [PadPrintFile(id: "1", title: "a.txt", code: "x")]
        )
        #expect(!markdown.contains("- **"))
        #expect(markdown.contains("## a.txt"))
    }

    @Test
    func `inline Markdown characters in text are escaped`() {
        let markdown = padMarkdownDocument(
            title: "snake_case *bold*",
            summary: [("Owner", "a_b <x>")],
            files: []
        )
        #expect(markdown.contains(#"# snake\_case \*bold\*"#))
        #expect(markdown.contains(#"a\_b \<x\>"#))
    }

    @Test
    func `clipboard links escape remote titles and delimit the validated URL`() throws {
        let url = try #require(URL(string: "https://example.com/pads/ABC123?next=(one)"))
        #expect(markdownLink(title: "[Ada]\nInterview", url: url)
            == "[\\[Ada\\] Interview](<https://example.com/pads/ABC123?next=(one)>)")
    }

    @Test
    func `line breaks in inline metadata cannot create Markdown blocks`() {
        let markdown = padMarkdownDocument(
            title: "Title\n# Injected heading",
            summary: [("Owner\n## Injected", "Ada\r\n- Injected item")],
            files: [PadPrintFile(id: "1", title: "main.py\r## Injected file", code: "print('hi')")]
        )

        #expect(markdown.contains("# Title # Injected heading\n"))
        #expect(markdown.contains("- **Owner ## Injected:** Ada - Injected item\n"))
        #expect(markdown.contains("## main.py ## Injected file\n"))
        #expect(!markdown.contains("\n# Injected heading"))
        #expect(!markdown.contains("\n## Injected file"))
        #expect(!markdown.contains("\n- Injected item"))
    }

    @Test
    func `test-case table cells collapse whitespace and bound remote values`() {
        #expect(markdownTableCell("one\n\t two   three") == "one two three")
        #expect(boundedMarkdownTestCaseInput(["one", "two"]) == "one, two")

        let oversized = String(repeating: "x", count: 1500)
        let bounded = markdownTableCell(oversized)
        #expect(bounded == String(repeating: "x", count: 1000) + "…")
        #expect(boundedMarkdownTestCaseInput([oversized]).count == 1001)
    }

    @Test
    func `code containing a triple-backtick run uses a safe tilde fence`() {
        let code = "let s = \"\"\"\n```\n\"\"\""
        let markdown = padMarkdownDocument(
            title: "T", summary: [],
            files: [PadPrintFile(id: "1", title: "f.swift", code: code, language: "swift")]
        )
        // A tilde fence is shorter than the four backticks the inner run requires.
        #expect(markdown.contains("~~~swift\n"))
        #expect(markdown.contains("\n~~~"))
    }

    @Test
    func `a pathological backtick run uses a short tilde fence`() {
        let code = String(repeating: "`", count: 10000)
        let markdown = padMarkdownDocument(
            title: "T", summary: [],
            files: [PadPrintFile(id: "1", title: "f.txt", code: code)]
        )

        #expect(markdown.contains("~~~\n\(code)\n~~~"))
    }

    @Test
    func `pathological runs of both delimiters use an indented block`() {
        let backticks = String(repeating: "`", count: 100)
        let tildes = String(repeating: "~", count: 100)
        let markdown = padMarkdownDocument(
            title: "T", summary: [],
            files: [PadPrintFile(id: "1", title: "f.txt", code: "\(backticks)\n\(tildes)")]
        )

        #expect(markdown.contains("    \(backticks)\n    \(tildes)"))
    }

    @Test
    func `language is normalized: multifile_ prefix dropped, nil yields a bare fence`() {
        let multifile = padMarkdownDocument(
            title: "T", summary: [],
            files: [PadPrintFile(id: "1", title: "a", code: "x", language: "multifile_python")]
        )
        #expect(multifile.contains("```python\n"))

        let none = padMarkdownDocument(
            title: "T", summary: [],
            files: [PadPrintFile(id: "1", title: "a", code: "x", language: nil)]
        )
        // A bare fence: three backticks immediately followed by the newline, no language.
        #expect(none.contains("```\nx\n```"))
    }

    @Test
    func `question document includes prompt materials and solution`() throws {
        let json = #"""
        {"id": 1, "title": "Two Sum", "language": "python3", "owner_email": "owner@example.com",
         "description": "Return indices for the **target**.",
         "candidate_instructions": [{"instructions": "Read the prompt.", "default_visible": true},
                                    {"instructions": "Use the helper.", "default_visible": false}],
         "test_cases_enabled": true,
         "test_cases": [{"id": 1, "arguments": ["[2,7]", "9"], "return_value": "[0,1]", "visible": false}],
         "custom_files": [{"id": "cf1", "title": "Starter", "description": "Boilerplate",
                           "filename": "main.py", "filesize": "1.2 KB"}],
         "contents": "def two_sum(nums, target):\n    pass",
         "contents_for_test_cases": "def check():\n    pass",
         "solution": "Use a hash map.", "used": 12, "public_take_home_setting_id": 42}
        """#
        let question = try CoderPadClient.decoder.decode(Question.self, from: Data(json.utf8))
        let markdown = questionMarkdownDocument(question, audience: .interviewer,
                                                sourceURL: URL(string: "https://app.coderpad.io/questions/1"),
                                                generatedAt: Date(timeIntervalSince1970: 1_721_044_800)) {
            $0 == "owner@example.com" ? "Ada" : $0
        }
        #expect(markdown.hasPrefix("# Two Sum\n"))
        #expect(markdown.contains("Generated: 2024-07-15T12:00:00Z"))
        #expect(markdown.contains("Source: <https://app.coderpad.io/questions/1>"))
        #expect(markdown.contains("- **Type:** Live"))
        #expect(markdown.contains("- **Language:** Python 3"))
        #expect(markdown.contains("- **Owner:** Ada"))
        #expect(markdown.contains("- **Times used:** 12"))
        #expect(markdown.contains("- **Public link:** Configured"))
        #expect(markdown.contains("## Description\n\n> Return indices for the **target**."))
        #expect(markdown.contains("### Part 2\n\n> Hidden by default\n\n> Use the helper."))
        // Brackets are escaped in table cells since a58c9d4's inline-metadata
        // hardening, so they can't read as Markdown link syntax.
        #expect(markdown.contains(#"| \[2,7\], 9 | \[0,1\] | Hidden |"#))
        #expect(markdown.contains("- main.py (1.2 KB): Boilerplate"))
        #expect(markdown.contains("```python3\ndef two_sum"))
        #expect(markdown.contains("## Starter Code (Test Cases)"))
        #expect(markdown.contains("## Solution\n\n> Use a hash map."))
        #expect(markdown.hasSuffix("\n"))
    }

    @Test
    func `remote Markdown bodies cannot escape their section`() {
        let body = "# Forged heading\n\n---\n<script>alert(1)</script>\n[Allowed link](https://example.com)"
        let isolated = isolatedMarkdownBody(body).joined(separator: "\n")

        #expect(isolated.contains("> # Forged heading"))
        #expect(isolated.contains("\n>\n> ---"))
        #expect(isolated.contains("&lt;script&gt;alert(1)&lt;/script&gt;"))
        #expect(isolated.contains("[Allowed link](https://example.com)"))
        #expect(!isolated.contains("\n# Forged heading"))
        #expect(!isolated.contains("<script>"))
    }

    @Test
    func `oversized prose and code are truncated before document assembly`() {
        let prose = String(repeating: "p", count: MarkdownExportLimits.proseCharacters + 1)
        let code = String(repeating: "c", count: MarkdownExportLimits.codeCharacters + 1)
        let markdown = padMarkdownDocument(
            title: "T", summary: [],
            files: [PadPrintFile(id: "1", title: "main.swift", code: code, language: "swift")]
        )

        #expect(isolatedMarkdownBody(prose).joined(separator: "\n").contains("Content truncated for export"))
        #expect(markdown.contains("// Content truncated for export."))
        #expect(!markdown.contains(String(repeating: "c", count: MarkdownExportLimits.codeCharacters + 1)))
    }

    @Test
    func `pad file collection is bounded with an explicit omission marker`() {
        let files = (0 ... MarkdownExportLimits.padFiles).map {
            PadPrintFile(id: String($0), title: "file-\($0)", code: "x")
        }

        let markdown = padMarkdownDocument(title: "T", summary: [], files: files)

        #expect(markdown.contains("_1 additional pad file omitted from this export._"))
        #expect(!markdown.contains("## file-\(MarkdownExportLimits.padFiles)\n"))
    }
}

@Suite("Code export paths")
struct CodeExportPathTests {
    @Test
    func `explanation key changes when contents or language changes`() {
        let original = CodeFile(id: "1", path: "main.swift", contents: "print(1)", language: "swift")
        let changedContents = CodeFile(id: "1", path: "main.swift", contents: "print(2)", language: "swift")
        let changedLanguage = CodeFile(id: "1", path: "main.swift", contents: "print(1)", language: "python")

        #expect(original.explanationKey != changedContents.explanationKey)
        #expect(original.explanationKey != changedLanguage.explanationKey)
    }

    @Test
    func `components drop traversal segments`() {
        let file = CodeFile(id: "1", path: "../src/./main.swift", contents: "", language: nil)

        #expect(CodeExportPathPlan.components(for: file) == ["src", "main.swift"])
    }

    @Test
    func `sanitized export root rejects dot only names`() {
        #expect(PadDetailView.sanitizeComponent(".") == "untitled")
        #expect(PadDetailView.sanitizeComponent("..") == "untitled")
        #expect(PadDetailView.sanitizeComponent(" ... ") == "untitled")
    }

    @Test
    func `unique relative paths preserve sanitized filename collisions`() {
        let paths = PadDetailView.uniqueRelativePaths([
            "src/foo-.js",
            "src/foo-.js",
            "src/foo-2.js",
            "src/foo-.js"
        ])

        #expect(paths == [
            "src/foo-.js",
            "src/foo--2.js",
            "src/foo-2.js",
            "src/foo--3.js"
        ])
    }

    @Test
    func `unique relative paths rename case-only collisions (#1040)`() {
        // Case-insensitive volumes (APFS default) treat README.md and readme.md as
        // one file, so the second must be renamed, keeping its own casing.
        let paths = PadDetailView.uniqueRelativePaths([
            "README.md",
            "readme.md",
            "src/Main.java",
            "src/main.java"
        ])

        #expect(paths == [
            "README.md",
            "readme-2.md",
            "src/Main.java",
            "src/main-2.java"
        ])
    }

    @Test
    func `folder download path plan renames exact and case-only collisions (#1040)`() {
        let files = [
            CodeFile(id: "1", path: "README.md", contents: "a", language: nil),
            CodeFile(id: "2", path: "readme.md", contents: "b", language: nil),
            CodeFile(id: "3", path: "readme.md", contents: "c", language: nil)
        ]

        #expect(CodeExportPathPlan.uniqueRelativePaths(for: files) == [
            "README.md",
            "readme-2.md",
            "readme-3.md"
        ])
    }

    @Test
    func `path plan rejects file directory collisions`() throws {
        let files = [
            CodeFile(id: "1", path: "src", contents: "", language: nil),
            CodeFile(id: "2", path: "src/main.swift", contents: "", language: nil)
        ]

        #expect(throws: CodeExportPathError.self) {
            try CodeExportPathPlan.validateNoFileDirectoryConflicts(files)
        }
    }

    @Test
    func `path plan rejects case-insensitive file directory collisions`() throws {
        let files = [
            CodeFile(id: "1", path: "foo", contents: "", language: nil),
            CodeFile(id: "2", path: "FOO/bar.swift", contents: "", language: nil)
        ]

        #expect(throws: CodeExportPathError.self) {
            try CodeExportPathPlan.validateNoFileDirectoryConflicts(files)
        }
    }

    @Test
    func `path plan rejects canonically equivalent file directory collisions`() throws {
        let files = [
            CodeFile(id: "1", path: "café", contents: "", language: nil),
            CodeFile(id: "2", path: "cafe\u{301}/menu.txt", contents: "", language: nil)
        ]

        #expect(throws: CodeExportPathError.self) {
            try CodeExportPathPlan.validateNoFileDirectoryConflicts(files)
        }
    }

    @Test
    func `path plan allows duplicate leaf files for later renaming`() throws {
        let files = [
            CodeFile(id: "1", path: "src/main.swift", contents: "", language: nil),
            CodeFile(id: "2", path: "src/main.swift", contents: "", language: nil)
        ]

        try CodeExportPathPlan.validateNoFileDirectoryConflicts(files)
    }

    /// The cheap emptiness check must agree with building the files (#2095), or the
    /// Save All Code command would enable and disable at the wrong times.
    @Test
    func `displayable-file check agrees with building the display files`() throws {
        func environment(_ files: [[String: Any]]) throws -> PadEnvironment {
            let data = try JSONSerialization.data(withJSONObject: ["id": 1, "file_contents": files])
            return try CoderPadClient.decoder.decode(PadEnvironment.self, from: data)
        }

        let empty = try environment([])
        // Files present, but none carrying contents: nothing to save.
        let blank = try environment([["path": "main.py", "contents": ""], ["path": "empty.py"]])
        let coded = try environment([["path": "main.py", "contents": ""],
                                     ["path": "util.py", "contents": "x = 1"]])

        #expect(!PadDetailView.hasDisplayableFiles(in: empty))
        #expect(!PadDetailView.hasDisplayableFiles(in: blank))
        #expect(PadDetailView.hasDisplayableFiles(in: coded))
    }
}
