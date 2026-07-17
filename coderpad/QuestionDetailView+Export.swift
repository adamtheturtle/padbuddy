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

        #if os(macOS)
            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = "\(name).md"
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
                defaultName: "\(questionExportFileName(name)).md"
            )
        #endif
    }

    #if !os(macOS)
        private func questionExportFileName(_ name: String) -> String {
            let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
            let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? "Untitled Question" : cleaned
        }
    #endif
}
