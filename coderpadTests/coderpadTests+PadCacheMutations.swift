//
//  coderpadTests+PadCacheMutations.swift
//  coderpadTests
//

@testable import CoderPad
import Foundation
import Testing

@Suite("Pad cache mutations")
struct PadCacheMutationTests {
    @Test func `question disk hydration publishes each identity once`() async throws {
        let question = try await CoderPadClient.mock(key: "cache-normalization-\(UUID().uuidString)")
            .getQuestion(id: 102)

        #expect(QuestionsCacheStore.normalizedDiskQuestions([question, question]) == [question])
    }

    @Test func `disk hydration keeps the first row for each pad identity`() {
        let first = Pad(id: "pad", title: "First")
        let duplicate = Pad(id: "pad", title: "Duplicate")
        let other = Pad(id: "other", title: "Other")

        #expect(PadsCacheStore.normalizedDiskPads([first, duplicate, other, duplicate]) == [first, other])
    }

    @Test func `fresh detail replaces every duplicate cached row`() {
        let stale = Pad(id: "pad", title: "Stale")
        let fresh = Pad(id: "pad", title: "Fresh")
        let updated = PadCacheMutation.replacing(fresh, in: [stale, stale])
        #expect(updated == [fresh, fresh])
    }

    @Test func `unchanged and absent authoritative lists do not rewrite`() {
        let pad = Pad(id: "pad", title: "Current")
        #expect(PadCacheMutation.replacing(pad, in: [pad]) == nil)
        #expect(PadCacheMutation.replacing(pad, in: []) == nil)
    }

    @Test func `a directly reached pad appends to an existing list`() {
        let existing = Pad(id: "one", title: "One")
        let direct = Pad(id: "two", title: "Two")
        #expect(PadCacheMutation.replacing(direct, in: [existing]) == [existing, direct])
    }
}
