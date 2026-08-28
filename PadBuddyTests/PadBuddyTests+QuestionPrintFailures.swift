//
//  PadBuddyTests+QuestionPrintFailures.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Question printing failures")
struct QuestionPrintFailureTests {
    private struct PrintFailure: LocalizedError {
        var errorDescription: String? {
            "Printer unavailable"
        }
    }

    @Test func `printing failure includes operation context for the alert`() {
        #expect(questionPrintFailureMessage(for: PrintFailure())
            == "Could not print this question — Printer unavailable")
    }

    @Test func `printing cancellation does not become an error alert`() {
        #expect(questionPrintFailureMessage(for: CancellationError()) == nil)
    }
}

@Suite("Printed content structure (#4724, #4725)")
struct PrintedContentStructureTests {
    @Test func `inline markdown parsing keeps paragraph breaks`() throws {
        let source = "First paragraph.\n\nSecond paragraph."

        let inline = try AttributedString(
            markdown: source,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        )

        // Full parsing turns the blank line into a presentation intent and drops the
        // newlines, which `Text(AttributedString)` does not render — so both paragraphs
        // printed as one run of text.
        #expect(String(inline.characters).contains("\n"))
        let full = try AttributedString(markdown: source)
        #expect(!String(full.characters).contains("\n"))
    }

    @Test func `inline markdown still applies inline styling`() throws {
        let inline = try AttributedString(
            markdown: "Some **bold** text",
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        )

        #expect(String(inline.characters) == "Some bold text")
        #expect(inline.runs.contains { $0.inlinePresentationIntent == .stronglyEmphasized })
    }
}
