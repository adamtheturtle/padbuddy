//
//  coderpadTests+PadCacheMutations.swift
//  coderpadTests
//

@testable import CoderPad
import Testing

@Suite("Pad cache mutations")
struct PadCacheMutationTests {
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
