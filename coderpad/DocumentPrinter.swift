//
//  DocumentPrinter.swift
//  coderpad
//
//  Print / Save-as-PDF (⌘P) support. SwiftUI has no print pipeline of its own on
//  macOS, so a focused detail's print-friendly rendering is hosted in an
//  `NSHostingView` and handed to `NSPrintOperation`, which drives the standard
//  print panel — and "Save as PDF" falls out of that panel for free.
//

import AppKit
import SwiftUI

/// Renders `content` to paper through the standard macOS print panel. The view is
/// laid out at the printable page width and sized to its fitting height, then
/// `NSPrintOperation` paginates anything taller than one page automatically.
///
/// The content is pinned to a light color scheme on a white background: paper is
/// white, and the app's adaptive colors would otherwise print as whatever the
/// current appearance happens to be (white-on-white in dark mode).
@MainActor
func printDocument(_ content: some View, jobTitle: String) {
    let info = NSPrintInfo()
    info.topMargin = 36
    info.bottomMargin = 36
    info.leftMargin = 36
    info.rightMargin = 36
    info.horizontalPagination = .fit
    info.verticalPagination = .automatic

    let contentWidth = info.paperSize.width - info.leftMargin - info.rightMargin

    let document = content
        .frame(width: contentWidth, alignment: .leading)
        .environment(\.colorScheme, .light)
        .background(Color.white)

    let hosting = NSHostingView(rootView: document)
    hosting.frame = NSRect(x: 0, y: 0, width: contentWidth, height: hosting.fittingSize.height)

    let operation = NSPrintOperation(view: hosting, printInfo: info)
    operation.jobTitle = jobTitle
    operation.run()
}

// MARK: - Print layout primitives

/// A titled block in a printed document — a small heading over its content, with
/// space below so sections don't run together across a page.
private struct PrintSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Code rendered for paper: plain wrapping monospaced text rather than the
/// on-screen syntax-highlighted, horizontally-scrolling view (which wouldn't
/// paginate). Wrapping keeps long lines on the page instead of clipping them.
private struct PrintCode: View {
    let code: String

    var body: some View {
        Text(code)
            .font(.system(.footnote, design: .monospaced))
            .textSelection(.disabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Question

/// A print-friendly rendering of a question: its title, key metadata, and the
/// prose an interviewer reads alongside a live interview — description, candidate
/// instructions, solution — plus starter code.
struct QuestionPrintDocument: View {
    let question: Question

    private var metaLine: String {
        var parts: [String] = [question.interviewType.label]
        if let language = question.language, !language.isEmpty {
            parts.append(language.languageDisplayName)
        }
        if let author = question.authorName, !author.isEmpty {
            parts.append(String(localized: "by \(author)"))
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(question.title.isEmpty ? String(localized: "Untitled Question") : question.title)
                    .font(.title.bold())
                Text(metaLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let description = question.description, !description.isEmpty {
                PrintSection(title: "Description") {
                    MarkdownText(description).font(.callout)
                }
            }

            if !question.candidateInstructions.isEmpty {
                PrintSection(title: "Candidate Instructions") {
                    VStack(alignment: .leading, spacing: 10) {
                        let instructions = question.candidateInstructions
                        ForEach(Array(instructions.enumerated()), id: \.offset) { index, item in
                            if instructions.count > 1 {
                                Text("Part \(index + 1)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            MarkdownText(item.instructions).font(.callout)
                        }
                    }
                }
            }

            if let contents = question.contents, !contents.isEmpty {
                PrintSection(title: "Starter Code") { PrintCode(code: contents) }
            }

            if let solution = question.solution, !solution.isEmpty {
                PrintSection(title: "Solution") {
                    MarkdownText(solution).font(.callout)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Pad

/// One code file in a printed pad, paired with the heading to label it.
struct PadPrintFile: Identifiable {
    let id: String
    let title: String
    let code: String
}

/// A print-friendly rendering of a pad: a summary header (type, state, owner,
/// participants, dates) followed by its code, one section per file.
struct PadPrintDocument: View {
    let pad: Pad
    let files: [PadPrintFile]
    /// Resolves an owner/participant email to a display name when known.
    var displayName: (String) -> String = \.self

    private var summaryRows: [(String, String)] {
        var rows: [(String, String)] = [
            ("Type", pad.interviewType?.label ?? "—"),
            ("State", pad.status.label),
            ("Owner", displayName(pad.ownerEmail))
        ]
        if let language = pad.language, !language.isEmpty {
            rows.append(("Language", language.languageDisplayName))
        }
        if !pad.participants.isEmpty {
            rows.append(("Participants", pad.participants.map(displayName).joined(separator: ", ")))
        }
        if let createdAt = pad.createdAt {
            rows.append(("Created", createdAt.formatted(date: .long, time: .shortened)))
        }
        if let endedAt = pad.endedAt {
            rows.append(("Ended", endedAt.formatted(date: .long, time: .shortened)))
        }
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(pad.title.isEmpty ? pad.id : pad.title)
                .font(.title.bold())

            PrintSection(title: "Summary") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(summaryRows.enumerated()), id: \.offset) { _, row in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(row.0)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 92, alignment: .leading)
                            Text(row.1)
                                .font(.callout)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }

            ForEach(files) { file in
                PrintSection(title: file.title) { PrintCode(code: file.code) }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
