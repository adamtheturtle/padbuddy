//
//  coderpadTests+HighlightedCodeLayout.swift
//  coderpadTests
//

@testable import CoderPad
import CoreGraphics
import Testing

@Suite("Highlighted code layout")
struct HighlightedCodeLayoutTests {
    @Test func `short embedded code hugs its contents`() {
        #expect(HighlightedCode.embeddedHeight(for: "let value = 1") < 180)
    }

    @Test func `long embedded code reaches but never exceeds its cap`() {
        let long = (1 ... 200).map { "line \($0)" }.joined(separator: "\n")
        #expect(HighlightedCode.embeddedHeight(for: long) == 360)
    }

    @Test func `empty embedded code keeps a usable minimum`() {
        #expect(HighlightedCode.embeddedHeight(for: "") == 72)
    }
}
