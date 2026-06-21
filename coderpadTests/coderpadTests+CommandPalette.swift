//
//  coderpadTests+CommandPalette.swift
//  coderpadTests
//
//  Tests for the command palette's fuzzy scorer (#526). The scorer is pure, so the
//  ranking it produces is tested directly, without any UI.
//

@testable import CoderPad
import Foundation
import Testing

@Suite("Command palette fuzzy scoring")
struct CommandPaletteFuzzyTests {
    @Test
    func `an empty query matches everything at a neutral score`() {
        #expect(paletteFuzzyScore("", "anything") == 0)
        #expect(paletteFuzzyScore("   ", "anything") == 0)
    }

    @Test
    func `an exact match scores highest and is case-insensitive`() {
        #expect(paletteFuzzyScore("reload", "Reload") == 1000)
    }

    @Test
    func `a prefix beats a mid-string substring beats a subsequence`() throws {
        let exact = try #require(paletteFuzzyScore("reload", "Reload"))
        let prefix = try #require(paletteFuzzyScore("rel", "Reload"))
        let substring = try #require(paletteFuzzyScore("pad", "New Pad"))
        let subsequence = try #require(paletteFuzzyScore("nwpd", "New Pad"))

        #expect(exact > prefix)
        #expect(prefix > substring)
        #expect(substring > subsequence)
    }

    @Test
    func `a non-match returns nil`() {
        #expect(paletteFuzzyScore("xyz", "Reload") == nil)
        // The needle's characters don't all appear in order.
        #expect(paletteFuzzyScore("zzz", "New Pad") == nil)
    }

    @Test
    func `a word-start substring outranks one mid-word`() throws {
        // "pad" starts the second word in "New Pad" (word-start bonus), but is mid-word
        // in "Notepads".
        let atWordStart = try #require(paletteFuzzyScore("pad", "New Pad"))
        let midWord = try #require(paletteFuzzyScore("pad", "Notepads"))
        #expect(atWordStart > midWord)
    }

    @Test
    func `a subsequence match still scores when characters are in order`() {
        // "npd" is a subsequence of "New Pad" (N…P…d) but not a substring.
        #expect(paletteFuzzyScore("npd", "New Pad") != nil)
        #expect(paletteFuzzyScore("npd", "New Pad") != 0)
    }
}
