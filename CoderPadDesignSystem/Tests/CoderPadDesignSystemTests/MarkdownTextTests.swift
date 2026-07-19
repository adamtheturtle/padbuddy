//
//  MarkdownTextTests.swift
//  CoderPadDesignSystemTests
//

@testable import CoderPadDesignSystem
import Testing

@Suite("Markdown plain-text fallback")
struct MarkdownTextTests {
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

        #expect(bounded.hasSuffix("\n\n_Content truncated for display._"))
        #expect(bounded.hasPrefix(String(repeating: family, count: MarkdownText.renderingLimit)))
        #expect(bounded.count < input.count)
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
