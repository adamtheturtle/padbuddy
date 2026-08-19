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
}
