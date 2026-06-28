//
//  DocumentPrinter.swift
//  coderpad
//
//  CoderPad's print-friendly document views (Cmd-P / Save-as-PDF). The generic print core -
//  `printDocument(_:jobTitle:)` and the `PrintSection`/`PrintCode` layout primitives - now
//  lives in buddy-kit's BuddyDesignSystem (#564), reaching the app via the
//  `@_exported import BuddyDesignSystem` umbrella in DesignSystem.swift. These views shape a
//  Question / Pad into a printable layout built from those primitives.
//

import SwiftUI

// MARK: - Question

/// A print-friendly rendering of a question: its title, key metadata, and the
/// prose an interviewer reads alongside a live interview - description, candidate
/// instructions, solution - plus starter code.
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
        // This document is rasterized by ImageRenderer (Print / Save-as-PDF). Tell the
        // selectable MarkdownText blocks above to drop their text-selection overlay, which
        // ImageRenderer can't flatten - otherwise each logs a SwiftUICore fault (#582).
        .environment(\.isRasterizedForPrint, true)
    }
}

// MARK: - Pad

/// One code file in a printed pad, paired with the heading to label it. The optional
/// language tags the Markdown export's code fence (it's unused by the print rendering).
struct PadPrintFile: Identifiable {
    let id: String
    let title: String
    let code: String
    var language: String?

    init(id: String, title: String, code: String, language: String? = nil) {
        self.id = id
        self.title = title
        self.code = code
        self.language = language
    }
}

/// The summary rows shown for a pad - its type, state, owner, and dates - shared by the
/// print rendering and the Markdown export (#524) so both describe a pad the same way.
/// `displayName` resolves an owner/participant email to a name when known.
func padSummaryRows(_ pad: Pad, displayName: (String) -> String = \.self) -> [(String, String)] {
    var rows: [(String, String)] = [
        ("Type", pad.interviewType?.label ?? "None"),
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

/// A print-friendly rendering of a pad: a summary header (type, state, owner,
/// participants, dates) followed by its code, one section per file.
struct PadPrintDocument: View {
    let pad: Pad
    let files: [PadPrintFile]
    /// Resolves an owner/participant email to a display name when known.
    var displayName: (String) -> String = \.self

    private var summaryRows: [(String, String)] {
        padSummaryRows(pad, displayName: displayName)
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
