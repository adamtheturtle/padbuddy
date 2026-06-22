//
//  BuddyAppKitTests.swift
//  BuddyAppKitTests
//
//  Smoke tests for the extracted zero-coupling utilities (#511): just enough to
//  prove the package compiles and the pure helpers behave, since the app's own
//  suites carry the full coverage once these are wired back in.
//

import BuddyAppKit
import Foundation
import Testing

@Suite("BuddyAppKit utilities")
struct BuddyAppKitTests {
    @Test
    func `primaryID prefers a newly added id, then any remaining, else nil`() {
        #expect(MultiSelectLogic.primaryID(previous: ["a"], current: ["a", "b"]) == "b")
        #expect(MultiSelectLogic.primaryID(previous: ["a", "b"], current: ["a"]) == "a")
        #expect(MultiSelectLogic.primaryID(previous: Set<String>(), current: []) == nil)
    }

    @Test
    func `staticURL builds a URL from a valid literal`() {
        #expect(URL.staticURL("https://example.com").absoluteString == "https://example.com")
        // `URL(string:)` is lenient (it percent-encodes most input), so the file-URL
        // fallback is a defensive last resort; what matters is staticURL never traps.
        #expect(!URL.staticURL("https://example.com/a b").absoluteString.isEmpty)
    }

    @Test
    func `LenientElement decodes a good value and nils a bad one without throwing`() throws {
        let good = try JSONDecoder().decode(LenientElement<Int>.self, from: Data("7".utf8))
        #expect(good.value == 7)

        let bad = try JSONDecoder().decode(LenientElement<Int>.self, from: Data("\"nope\"".utf8))
        #expect(bad.value == nil)
    }
}
