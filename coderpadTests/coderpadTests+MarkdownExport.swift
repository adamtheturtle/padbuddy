//
//  coderpadTests+MarkdownExport.swift
//  coderpadTests
//
//  Tests for the pad Markdown export (#524): document structure, inline escaping, code
//  fence sizing, and language normalization. The builder is pure, so it's tested without
//  any UI or network.
//

@testable import CoderPad
import Foundation
import Testing

@Suite("Pad Markdown export")
struct PadMarkdownExportTests {
    @Test
    func `document has a title, a summary list, and a fenced block per file`() {
        let markdown = padMarkdownDocument(
            title: "Phone Screen",
            summary: [("Type", "Interview"), ("Owner", "Ada")],
            files: [
                PadPrintFile(id: "1", title: "main.py", code: "print('hi')", language: "python"),
                PadPrintFile(id: "2", title: "test.py", code: "assert True", language: "python")
            ]
        )

        #expect(markdown.hasPrefix("# Phone Screen\n"))
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
    func `code containing a triple-backtick run gets a longer fence`() {
        let code = "let s = \"\"\"\n```\n\"\"\""
        let markdown = padMarkdownDocument(
            title: "T", summary: [],
            files: [PadPrintFile(id: "1", title: "f.swift", code: code, language: "swift")]
        )
        // The inner ``` run forces a 4-backtick fence so the block isn't closed early.
        #expect(markdown.contains("````swift\n"))
        #expect(markdown.contains("\n````"))
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
        let markdown = questionMarkdownDocument(question) { $0 == "owner@example.com" ? "Ada" : $0 }

        #expect(markdown.hasPrefix("# Two Sum\n"))
        #expect(markdown.contains("- **Type:** Live"))
        #expect(markdown.contains("- **Language:** Python 3"))
        #expect(markdown.contains("- **Owner:** Ada"))
        #expect(markdown.contains("- **Times used:** 12"))
        #expect(markdown.contains("- **Public link:** Configured"))
        #expect(markdown.contains("## Description\n\nReturn indices for the **target**."))
        #expect(markdown.contains("### Part 2\n\n> Hidden by default\n\nUse the helper."))
        // Brackets are escaped in table cells since a58c9d4's inline-metadata
        // hardening, so they can't read as Markdown link syntax.
        #expect(markdown.contains(#"| \[2,7\], 9 | \[0,1\] | Hidden |"#))
        #expect(markdown.contains("- main.py (1.2 KB): Boilerplate"))
        #expect(markdown.contains("```python3\ndef two_sum"))
        #expect(markdown.contains("## Starter Code (Test Cases)"))
        #expect(markdown.contains("## Solution\n\nUse a hash map."))
        #expect(markdown.hasSuffix("\n"))
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
    func `path plan allows duplicate leaf files for later renaming`() throws {
        let files = [
            CodeFile(id: "1", path: "src/main.swift", contents: "", language: nil),
            CodeFile(id: "2", path: "src/main.swift", contents: "", language: nil)
        ]

        try CodeExportPathPlan.validateNoFileDirectoryConflicts(files)
    }
}
