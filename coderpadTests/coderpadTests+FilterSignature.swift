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

    @Test
    func `filter text ignores surrounding whitespace and case`() {
        #expect(FilterSignature.make(["  Alice ", "PYTHON"])
            == FilterSignature.make(["alice", "python"]))
    }

    @Test
    func `exact identity preserves case and whitespace`() {
        #expect(FilterSignature.makeExact([" Key "]) != FilterSignature.makeExact(["key"]))
    }
}
