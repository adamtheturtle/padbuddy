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
    func printQuestionDocument(audience: QuestionDocumentAudience) {
        #if os(macOS) || os(iOS)
        let configuration = PrintableView.PrintConfiguration(
            footer: .attribution(sourceURL: question.webURL(baseURL: client.baseURL)),
            jobTitle: question.displayTitle
        )
        try? PrintableView.printDocument(configuration: configuration) {
            QuestionPrintDocument(question: question, audience: audience)
        }
        #endif
    }

    /// Writes the question as a single Markdown document: summary, prompt,
    /// instructions, materials, starter code, and solution where present.
    func exportMarkdown(audience: QuestionDocumentAudience) {
        let name = question.displayTitle
        let document = questionMarkdownDocument(
            question,
            audience: audience,
            sourceURL: question.webURL(baseURL: client.baseURL),
            displayName: directory.display
        )
        // The title is remote content: sanitize the suggested filename on both
        // platforms — the macOS panel previously took the raw title, so path
        // separators/control characters produced invalid or misleading suggested
        // names (#1162).
        let fileName = SaveCodePathHelpers.sanitizeComponent(name)

        #if os(macOS)
            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = "\(fileName).md"
            panel.message = String(localized: "Export \"\(name)\" as Markdown")
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

    func exportAudienceDialog(_ content: some View) -> some View {
        content.confirmationDialog(
            "Choose Export Audience",
            isPresented: $showExportAudienceOptions,
            titleVisibility: .visible
        ) {
            Button("Candidate Copy") { exportMarkdown(audience: .candidate) }
            Button("Interviewer Copy (Includes Confidential Content)") {
                exportMarkdown(audience: .interviewer)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Interviewer copies can contain hidden instructions and the reference solution. "
                + "Review before sharing.")
        }
    }

    func printAudienceDialog(_ content: some View) -> some View {
        content.confirmationDialog(
            "Choose Print Audience",
            isPresented: $showPrintAudienceOptions,
            titleVisibility: .visible
        ) {
            Button("Candidate Copy") { printQuestionDocument(audience: .candidate) }
            Button("Interviewer Copy (Includes Confidential Content)") {
                printQuestionDocument(audience: .interviewer)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Interviewer copies can contain hidden instructions and the reference solution. "
                + "Review before sharing.")
        }
    }
}
