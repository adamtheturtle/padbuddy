//
//  coderpadTests+CodeExplanationParsing.swift
//  coderpadTests
//

@testable import CoderPad
import Testing

@Suite("Code explanation plain text")
struct CodeExplanationPlainTextTests {
    @Test
    func `copy text includes visible sections and truncation warning`() {
        let explanation = CodeExplanation(
            summary: "Uses a lookup table.",
            readability: "Clear names.",
            optimality: "O(n) time.",
            sourceWasTruncated: true
        )

        #expect(explanation.plainText.contains("This explanation covers only the beginning of the file."))
        #expect(explanation.plainText.contains("What it does\nUses a lookup table."))
        #expect(explanation.plainText.contains("Quality & readability\nClear names."))
        #expect(explanation.plainText.contains("Time & space complexity\nO(n) time."))
    }
}

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
