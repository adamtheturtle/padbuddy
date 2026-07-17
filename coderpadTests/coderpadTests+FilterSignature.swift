//
//  coderpadTests+FilterSignature.swift
//  coderpadTests
//

@testable import CoderPad
import Testing

@Suite("Filter signatures")
struct FilterSignatureTests {
    @Test
    func `delimiter-like values do not collide across fields`() {
        let combinedSearch = FilterSignature.make(["a|python", nil])
        let splitSearchAndLanguage = FilterSignature.make(["a", "python"])

        #expect(combinedSearch != splitSearchAndLanguage)
    }

    @Test
    func `literal nil sentinel text does not collide with nil`() {
        #expect(FilterSignature.make(["·"]) != FilterSignature.make([nil]))
    }
}
