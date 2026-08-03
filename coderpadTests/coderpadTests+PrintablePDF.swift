//
//  coderpadTests+PrintablePDF.swift
//  coderpadTests
//
//  End-to-end PDF regression coverage for the app's question and pad documents.
//

@testable import CoderPad
import PDFKit
import PrintableView
import SwiftUI
import Testing

@MainActor
@Suite("Printable PDF documents (#4157)")
struct PrintablePDFTests {
    private let letter = CGSize(width: 612, height: 792)

    @Test func `multi-page question retains attribution and representative content`() throws {
        let source = URL(string: "https://app.coderpad.io/questions/4157")!
        let repeatedPrompt = Array(
            repeating: "Explain the invariant, evaluate the trade-offs, and include a worked example.",
            count: 90
        ).joined(separator: "\n\n")
        let object: [String: Any] = [
            "id": 4157,
            "title": "Distributed Queue Design",
            "language": "swift",
            "description": repeatedPrompt,
            "candidate_instructions": [["instructions": "Preserve FIFO ordering.", "default_visible": true]],
            "contents": "struct QueueSentinel { let value = 4157 }",
            "solution": "Use partition-local sequence numbers."
        ]
        let question = try CoderPadClient.decoder.decode(
            Question.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        let data = try PrintableView.renderPDF(
            QuestionPrintDocument(question: question, audience: .interviewer),
            configuration: configuration(source: source, title: question.title)
        )
        attachArtifact(data, name: "question-print-regression.pdf")

        let document = try #require(PDFDocument(data: data))
        #expect((2 ... 12).contains(document.pageCount))
        expectAttribution(source.absoluteString, onEveryPageOf: document)
        let text = allText(in: document)
        // Markdown-backed prose is intentionally rasterized for reliable printing,
        // while section headings and PrintCode remain searchable vector text.
        #expect(text.contains("Candidate Instructions"))
        #expect(text.contains("Starter Code"))
        #expect(text.contains("QueueSentinel"))
        #expect(text.contains("Solution"))
    }

    @Test func `multi-file pad retains attribution headings and code`() throws {
        let source = URL(string: "https://app.coderpad.io/pads/PDF4157")!
        let padJSON = #"""
        {"id":"PDF4157","title":"Multi-file PDF Fixture","state":"ended","language":"swift",
         "url":"https://app.coderpad.io/PDF4157"}
        """#
        let pad = try CoderPadClient.decoder.decode(
            Pad.self,
            from: Data(padJSON.utf8)
        )
        let files = (1 ... 24).map { index in
            PadPrintFile(
                id: String(index),
                title: "Module\(index).swift",
                code: "struct Module\(index)Sentinel { let value = \(index) }\n"
                    + String(repeating: "// printable line\n", count: 12),
                language: "swift"
            )
        }
        let data = try PrintableView.renderPDF(
            PadPrintDocument(pad: pad, files: files),
            configuration: configuration(source: source, title: pad.title)
        )
        attachArtifact(data, name: "pad-print-regression.pdf")

        let document = try #require(PDFDocument(data: data))
        #expect((2 ... 20).contains(document.pageCount))
        expectAttribution(source.absoluteString, onEveryPageOf: document)
        let text = allText(in: document)
        #expect(text.contains("Multi-file PDF Fixture"))
        #expect(text.contains("Module1.swift"))
        #expect(text.contains("Module24.swift"))
        #expect(text.contains("Module24Sentinel"))
    }

    private func configuration(source: URL, title: String) -> PrintableView.PrintConfiguration {
        PrintableView.PrintConfiguration(
            pageSize: letter,
            footer: .attribution(sourceURL: source),
            jobTitle: title
        )
    }

    private func expectAttribution(_ source: String, onEveryPageOf document: PDFDocument) {
        #expect(document.pageCount > 1)
        for index in 0 ..< document.pageCount {
            let text = document.page(at: index)?.string ?? ""
            #expect(text.contains(source), "Page \(index + 1) is missing source attribution")
            #expect(text.contains("Page \(index + 1) of \(document.pageCount)"))
        }
    }

    private func allText(in document: PDFDocument) -> String {
        (0 ..< document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
    }

    /// Recording before assertions embeds the rendered document in the xcresult,
    /// which the Fast CI job retains whenever a regression fails.
    private func attachArtifact(_ data: Data, name: String) {
        Attachment<[UInt8]>.record(Array(data), named: name)
    }
}
