//
//  PadBuddyTests+HighlightedCodeLayout.swift
//  PadBuddyTests
//

import CoreGraphics
@testable import PadBuddy
import Testing

@Suite("Highlighted code layout")
struct HighlightedCodeLayoutTests {
    @Test func `short embedded code hugs its contents`() {
        #expect(embeddedHeight(for: "let value = 1") < 180)
    }

    @Test func `long embedded code reaches but never exceeds its cap`() {
        let long = (1 ... 200).map { "line \($0)" }.joined(separator: "\n")
        #expect(embeddedHeight(for: long) == 360)
    }

    @Test func `empty embedded code keeps a usable minimum`() {
        #expect(embeddedHeight(for: "") == 72)
    }

    private func embeddedHeight(for contents: String) -> CGFloat {
        HighlightedCode(contents: "", language: nil, dark: false).embeddedHeight(for: contents)
    }
}
