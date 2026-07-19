//
//  coderpadTests+CodeExplanationParsing.swift
//  coderpadTests
//

@testable import CoderPad
import Testing

#if canImport(FoundationModels)
    @Suite("Code explanation parsing")
    struct CodeExplanationParsingTests {
        @Test
        func `every label is required exactly once and in order`() {
            let valid = """
            SUMMARY: Does the work.
            READABILITY: Clear.
            OPTIMALITY: O(n) time and O(1) space.
            """

            #expect(PadCodeExplainer.parseExplanation(valid) != nil)
            #expect(PadCodeExplainer.parseExplanation(valid + "\nSUMMARY: Conflicting suffix.") == nil)
            #expect(PadCodeExplainer.parseExplanation("SUMMARY: Partial only.") == nil)
            #expect(PadCodeExplainer.parseExplanation("READABILITY: Clear.\n" + valid) == nil)
        }
    }
#endif
