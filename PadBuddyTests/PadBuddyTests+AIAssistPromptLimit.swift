//
//  PadBuddyTests+AIAssistPromptLimit.swift
//  PadBuddyTests
//

import Testing
@testable import PadBuddy

@Suite("AI Assist system prompt word limit")
struct AIAssistSystemPromptLimitTests {
    @Test func `counts words separated by mixed whitespace`() {
        #expect(AIAssistSystemPromptLimit.wordCount(in: "one\ttwo\n three  four") == 4)
    }

    @Test func `punctuation remains part of its surrounding word`() {
        #expect(AIAssistSystemPromptLimit.wordCount(in: "Explain arrays, maps, and sets.") == 5)
    }

    @Test func `status describes the allowed boundary`() {
        let prompt = Array(repeating: "word", count: 400).joined(separator: " ")
        #expect(AIAssistSystemPromptLimit.statusText(for: prompt) == "400 of 400 words")
    }

    @Test func `status calls out words beyond the limit`() {
        let prompt = Array(repeating: "word", count: 403).joined(separator: " ")
        #expect(AIAssistSystemPromptLimit.statusText(for: prompt) == "403 words — 3 over the 400-word limit")
    }
}
