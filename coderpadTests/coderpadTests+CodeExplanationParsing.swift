//
//  coderpadTests+CodeExplanationParsing.swift
//  coderpadTests
//

@testable import CoderPad
import Testing

@Suite("Code explanation plain text")
struct CodeExplanationPlainTextTests {
    @Test
    func `file selection survives refresh while its identity remains available`() {
        #expect(reconciledCodeFileSelection(current: "main.swift", availableIDs: ["main.swift", "new.swift"])
            == "main.swift")
        #expect(reconciledCodeFileSelection(current: "removed.swift", availableIDs: ["main.swift"]) == nil)
    }

    @Test
    func `code revision is stable and changes with contents`() {
        let original = stableCodeRevisionIdentifier("print(1)")

        #expect(original == stableCodeRevisionIdentifier("print(1)"))
        #expect(original != stableCodeRevisionIdentifier("print(2)"))
        #expect(original.count == 12)
    }

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
        #expect(explanation.plainText(revisionIdentifier: "a1b2c3").hasPrefix("Code revision: a1b2c3"))
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
