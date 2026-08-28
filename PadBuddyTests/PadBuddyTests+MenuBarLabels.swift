//
//  PadBuddyTests+MenuBarLabels.swift
//  PadBuddyTests
//

#if os(macOS)
    import Foundation
    @testable import PadBuddy
    import Testing

    @Suite("Menu bar label sanitization (#4749)")
    struct MenuBarLabelTests {
        @Test func `an ordinary title is kept`() {
            #expect(MenuBarView.safeMenuLabel("Interview with Ada", fallback: "Pad") == "Interview with Ada")
        }

        @Test func `a bidi override cannot reorder the label`() {
            // U+202E can make the rendered label read as a different pad than the item opens.
            let label = MenuBarView.safeMenuLabel("safe\u{202E}gnp.exe", fallback: "Pad")

            #expect(!label.unicodeScalars.contains { $0.properties.generalCategory == .format })
            #expect(label == "safegnp.exe")
        }

        @Test(arguments: ["\u{2066}", "\u{2067}", "\u{2068}", "\u{2069}", "\u{200D}", "\u{200B}"])
        func `format scalars are stripped`(scalar: String) {
            let label = MenuBarView.safeMenuLabel("a\(scalar)b", fallback: "Pad")

            #expect(!label.unicodeScalars.contains { $0.properties.generalCategory == .format })
        }

        @Test func `a title of only format scalars falls back`() {
            #expect(MenuBarView.safeMenuLabel("\u{202E}\u{2066}", fallback: "Untitled") == "Untitled")
        }

        @Test func `whitespace is still collapsed and the length still capped`() {
            #expect(MenuBarView.safeMenuLabel("a \n\t b", fallback: "Pad") == "a b")
            #expect(MenuBarView.safeMenuLabel(String(repeating: "x", count: 500), fallback: "Pad").count == 160)
        }
    }
#endif
