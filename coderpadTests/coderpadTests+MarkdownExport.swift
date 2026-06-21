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
}
