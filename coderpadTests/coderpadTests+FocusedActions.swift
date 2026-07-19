//
//  coderpadTests+FocusedActions.swift
//  coderpadTests
//

@testable import CoderPad
#if os(macOS)
    import AppKit
#endif
import Testing
import UniformTypeIdentifiers

@Suite("Focused actions")
struct FocusedActionsTests {
    #if os(macOS)
        @Test
        func `copy-link provider publishes URL and text representations`() throws {
            let command = try #require(copyLinkCommand(hasSelection: true) { "https://example.com/pad/abc" })
            let provider = try #require(command().first)

            #expect(provider.hasItemConformingToTypeIdentifier(UTType.url.identifier))
            #expect(provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier))
            #expect(copyLinkCommand(hasSelection: false) { "https://example.com" } == nil)
        }

        @Test
        func `multi-link pasteboard removes empty and duplicate links stably`() throws {
            let item = try #require(multiLinkPasteboardItem([
                "https://example.com/a",
                "",
                "https://example.com/b",
                "https://example.com/a"
            ]))

            #expect(item.string(forType: .URL) == "https://example.com/a")
            #expect(item.string(forType: .string) == "https://example.com/a\nhttps://example.com/b")
            #expect(multiLinkPasteboardItem(["", ""]) == nil)
        }
    #endif
}
