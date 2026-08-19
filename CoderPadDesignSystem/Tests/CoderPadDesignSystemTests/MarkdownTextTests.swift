//
//  MarkdownTextTests.swift
//  CoderPadDesignSystemTests
//

@testable import CoderPadDesignSystem
import Foundation
import Testing

@Suite("Markdown plain-text fallback")
struct MarkdownTextTests {
    @Test
    func `remote links default to credential-free web URLs`() throws {
        #expect(try MarkdownText.isSafeRemoteLink(#require(URL(string: "https://example.com/path"))))
        #expect(try MarkdownText.isSafeRemoteLink(#require(URL(string: "http://localhost:8080/help"))))
        #expect(try !MarkdownText.isSafeRemoteLink(#require(URL(string: "javascript:alert(1)"))))
        #expect(try !MarkdownText.isSafeRemoteLink(#require(URL(string: "coderpad://open/pad"))))
        #expect(try !MarkdownText.isSafeRemoteLink(#require(URL(string: "https://user:secret@example.com"))))
    }

    @Test(arguments: ["%E2%80%AA", "%E2%80%AE", "%E2%81%A6", "%E2%81%A7", "%E2%81%A8", "%E2%81%A9"])
    func `remote links reject percent-encoded bidi controls`(encodedControl: String) throws {
        let url = try #require(URL(string: "https://example.com/path?next=\(encodedControl)target"))

        #expect(!MarkdownText.isSafeRemoteLink(url))
    }

    @Test
    func `normal rendering input is unchanged`() {
        let markdown = "# Heading\n\nOrdinary **content**."
        #expect(MarkdownText.boundedRenderingInput(markdown) == markdown)
    }

    @Test
    func `oversized rendering input is bounded with a marker`() {
        let family = "👨‍👩‍👧‍👦"
        let input = String(repeating: family, count: MarkdownText.renderingLimit + 100)
        let bounded = MarkdownText.boundedRenderingInput(input)
        let marker = "\n\n_Content truncated for display._"

        #expect(bounded.hasSuffix(marker))
        #expect(bounded.utf8.count <= MarkdownText.renderingLimit + marker.utf8.count)
        #expect(bounded.utf8.count < input.utf8.count)
    }

    @Test
    func `one giant combining grapheme is bounded before rendering`() {
        let input = "a" + String(repeating: "\u{0301}", count: MarkdownText.renderingLimit)
        #expect(input.count == 1)

        let bounded = MarkdownText.boundedRenderingInput(input)

        #expect(bounded.hasSuffix("\n\n_Content truncated for display._"))
        #expect(bounded.utf8.count < input.utf8.count)
    }

    @Test
    func `ordinary content is preserved while unsafe whitespace is normalized`() {
        #expect(MarkdownText.plainTextFallback("  Hello\n\tworld\u{0000}  ") == "Hello world")
        #expect(MarkdownText.plainTextFallback("**literal** [link](https://example.com)")
            == "**literal** [link](https://example.com)")
    }

    @Test(arguments: ["\u{202A}", "\u{202E}", "\u{2066}", "\u{2067}", "\u{2068}", "\u{2069}"])
    func `bidi format scalar is stripped from a mixed grapheme`(control: String) {
        let mixed = "a\(control)\u{0301}b"

        #expect(MarkdownText.plainTextFallback(mixed) == "a\u{0301}b")
    }

    @Test
    func `empty unsafe content has an explicit fallback`() {
        #expect(MarkdownText.plainTextFallback("\u{200B}\u{0000}") == "(empty)")
    }

    @Test
    func `oversized content is bounded by grapheme cluster`() {
        let family = "👨‍👩‍👧‍👦"
        let value = MarkdownText.plainTextFallback(
            String(repeating: family, count: MarkdownText.plainTextFallbackLimit + 10)
        )

        #expect(value.count == MarkdownText.plainTextFallbackLimit)
        #expect(value.last == Character(family))
    }

    @Test
    func `multi-megabyte fallback is bounded before normalization`() {
        let input = String(repeating: "word ", count: 1_000_000) + "unreachable-suffix"

        let value = MarkdownText.plainTextFallback(input)

        #expect(value.count == MarkdownText.plainTextFallbackLimit)
        #expect(!value.contains("unreachable-suffix"))
    }
}
