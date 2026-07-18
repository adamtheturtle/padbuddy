//
//  DocumentPrinter.swift
//  coderpad
//
//  CoderPad's print-friendly document views (Cmd-P / Save-as-PDF). The generic print core -
//  `printDocument(_:jobTitle:)` and the `PrintSection`/`PrintCode` layout primitives - now
//  lives in PrintableView (#652), reaching the app via the `@_exported import PrintableView`
//  umbrella in DesignSystem.swift. These views shape a Question / Pad into a printable
//  layout built from those primitives.
//

import PrintableView
import SwiftUI

// MARK: - Question

/// A print-friendly rendering of a question: its title, key metadata, and the
/// prose an interviewer reads alongside a live interview - description, candidate
/// instructions, solution - plus starter code.
struct QuestionPrintDocument: View {
    let question: Question

    /// Trimmed, so a whitespace-only title falls back to the placeholder instead of
    /// printing a blank heading (#1950).
    private var displayTitle: String {
        let trimmed = question.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "Untitled Question") : trimmed
    }

    /// Whether any printable section will render, so an all-empty question gets an
    /// explicit note rather than a bare title over blank paper (#1956).
    private var hasPrintableContent: Bool {
        !(question.description ?? "").isEmpty
            || !question.candidateInstructions.isEmpty
            || !(question.contents ?? "").isEmpty
            || !(question.solution ?? "").isEmpty
    }

    private var metaLine: String {
        var parts: [String] = [question.interviewType.label]
        if let language = question.language, !language.isEmpty {
            parts.append(language.coderPadLanguageDisplayName)
        }
        if let author = question.authorName, !author.isEmpty {
            parts.append(String(localized: "by \(author)"))
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(displayTitle)
                    .font(.title.bold())
                Text(metaLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !hasPrintableContent {
                Text("This question has no description, candidate instructions, starter code, or solution to print.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let description = question.description, !description.isEmpty {
                PrintableView.PrintSection(title: "Description") {
                    MarkdownText(description).font(.callout)
                }
            }

            if !question.candidateInstructions.isEmpty {
                PrintableView.PrintSection(title: "Candidate Instructions") {
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
                PrintableView.PrintSection(title: "Starter Code") { PrintableView.PrintCode(code: contents) }
            }

            if let solution = question.solution, !solution.isEmpty {
                PrintableView.PrintSection(title: "Solution") {
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
        rows.append(("Language", language.coderPadLanguageDisplayName))
    }
    if !pad.participants.isEmpty {
        // The API can repeat a participant across sessions; a printed summary should
        // name each person once (#1955).
        var seen = Set<String>()
        let unique = pad.participants.filter { seen.insert($0.lowercased()).inserted }
        rows.append(("Participants", unique.map(displayName).joined(separator: ", ")))
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

    /// Trimmed, so a whitespace-only title falls back to the pad id instead of a
    /// blank heading (#1951).
    private var displayTitle: String {
        let trimmed = pad.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? pad.id : trimmed
    }

    /// Files with guaranteed-unique SwiftUI identities and disambiguated headings:
    /// file ids come from the server and can repeat (#1952), and two files can share
    /// one display name, which would make their printed sections indistinguishable
    /// (#1953).
    private var displayFiles: [PadPrintFile] {
        var seenIDs: Set<String> = []
        var titleCounts: [String: Int] = [:]
        for file in files { titleCounts[file.title, default: 0] += 1 }
        var titleOrdinals: [String: Int] = [:]
        return files.map { file in
            var id = file.id
            while !seenIDs.insert(id).inserted { id += "+" }
            var title = file.title
            if titleCounts[file.title, default: 0] > 1 {
                let ordinal = (titleOrdinals[file.title] ?? 0) + 1
                titleOrdinals[file.title] = ordinal
                title = "\(file.title) (\(ordinal))"
            }
            return PadPrintFile(id: id, title: title, code: file.code, language: file.language)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(displayTitle)
                .font(.title.bold())

            PrintableView.PrintSection(title: "Summary") {
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

            ForEach(displayFiles) { file in
                PrintableView.PrintSection(title: file.title) { PrintableView.PrintCode(code: file.code) }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
