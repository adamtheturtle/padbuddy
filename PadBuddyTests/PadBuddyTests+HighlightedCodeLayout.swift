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

@Suite("Highlighted code derived source (#4743)")
struct HighlightedCodeDerivedSourceTests {
    @Test func `the accessibility label numbers every line`() {
        let derived = HighlightedCode.DerivedSource()

        derived.refresh(contents: "alpha\nbeta")

        #expect(derived.accessibleSource == "Line 1, alpha\nLine 2, beta")
        #expect(derived.lineCount == 2)
    }

    @Test func `an unchanged source is not rebuilt`() {
        let derived = HighlightedCode.DerivedSource()
        derived.refresh(contents: "alpha")
        let first = derived.accessibleSource

        derived.refresh(contents: "alpha")

        #expect(derived.accessibleSource == first)
    }

    @Test func `a changed source is rebuilt`() {
        let derived = HighlightedCode.DerivedSource()
        derived.refresh(contents: "alpha")

        derived.refresh(contents: "beta\ngamma")

        #expect(derived.accessibleSource == "Line 1, beta\nLine 2, gamma")
        #expect(derived.lineCount == 2)
    }

    @Test func `empty source still counts as one line`() {
        let derived = HighlightedCode.DerivedSource()

        derived.refresh(contents: "")

        #expect(derived.lineCount == 1)
    }
}
