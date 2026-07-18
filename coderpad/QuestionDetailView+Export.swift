//
//  QuestionDetailView+Export.swift
//  coderpad
//

#if os(macOS)
    import AppKit
#else
    import UniformTypeIdentifiers
#endif
import SwiftUI

extension QuestionDetailView {
    /// Renders the question as a printable document. Shared by File > Print and
    /// iPad's document overflow menu so both routes stay in sync.
    func printQuestionDocument() {
        printDocument(QuestionPrintDocument(question: question),
                      jobTitle: question.displayTitle)
    }

    /// Writes the question as a single Markdown document: summary, prompt,
    /// instructions, materials, starter code, and solution where present.
    func exportMarkdown() {
        let name = question.displayTitle
        let document = questionMarkdownDocument(question, displayName: directory.display)
        // The title is remote content: sanitize the suggested filename on both
        // platforms — the macOS panel previously took the raw title, so path
        // separators/control characters produced invalid or misleading suggested
        // names (#1162).
        let fileName = SaveCodePathHelpers.sanitizeComponent(name)

        #if os(macOS)
            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = "\(fileName).md"
            panel.message = "Export \"\(name)\" as Markdown"
            guard panel.runModal() == .OK, let url = panel.url else { return }

            do {
                try document.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                editError = error.localizedDescription
            }
        #else
            pendingExport = PadExportDocument(
                text: document,
                contentType: .plainText,
                defaultName: "\(fileName).md"
            )
        #endif
    }
}
