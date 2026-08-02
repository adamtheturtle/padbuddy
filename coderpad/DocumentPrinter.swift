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

// swiftlint:disable file_length

import PrintableView
import SwiftUI

/// Bounds text handed to ImageRenderer-backed print views. Character indexing keeps
/// truncation on a grapheme boundary, so composed Unicode is never split (#1550).
struct PrintContentBudget {
    static let maximumCharacters = 200_000
    static let maximumFiles = 100
    static let maximumSections = 100

    private(set) var remainingCharacters: Int

    init(maximumCharacters: Int = Self.maximumCharacters) {
        remainingCharacters = max(0, maximumCharacters)
    }

    static func boundedLabel(_ text: String, maximumCharacters: Int = 512) -> String {
        String(text.prefix(max(0, maximumCharacters)))
    }

    mutating func consume(_ text: String) -> (text: String, truncated: Bool) {
        guard remainingCharacters > 0 else { return ("", !text.isEmpty) }
        guard let limit = text.index(text.startIndex, offsetBy: remainingCharacters, limitedBy: text.endIndex) else {
            remainingCharacters -= text.count
            return (text, false)
        }
        guard limit != text.endIndex else {
            remainingCharacters = 0
            return (text, false)
        }

        remainingCharacters = 0
        return (String(text[..<limit]), true)
    }
}

// MARK: - Question

/// A print-friendly rendering of a question: its title, key metadata, and the
/// prose an interviewer reads alongside a live interview - description, candidate
/// instructions, solution - plus starter code.
struct QuestionPrintDocument: View {
    let question: Question
    private let printableDescription: String
    private let printableInstructions: [String]
    private let printableContents: String
    private let printableSolution: String
    private let printableAIAssistSystemPrompt: String
    private let truncationSummary: String?

    static func includedInstructions(
        _ instructions: [CandidateInstruction], audience: QuestionDocumentAudience
    ) -> [CandidateInstruction] {
        audience == .interviewer ? instructions : instructions.filter(\.defaultVisible)
    }

    static func includedSolution(_ solution: String?, audience: QuestionDocumentAudience) -> String {
        audience == .interviewer ? solution ?? "" : ""
    }

    static func includedAIAssistSystemPrompt(_ prompt: String?, audience: QuestionDocumentAudience) -> String {
        guard audience == .interviewer, let prompt else { return "" }
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }

        return prompt
    }

    init(question: Question, audience: QuestionDocumentAudience = .candidate) {
        self.question = question
        var budget = PrintContentBudget()
        let includedInstructions = Self.includedInstructions(question.candidateInstructions, audience: audience)
        var truncatedSections: [String] = includedInstructions.count > PrintContentBudget.maximumSections
            ? [String(localized: "Candidate Instructions")] : []

        let description = budget.consume(question.description ?? "")
        printableDescription = description.text
        if description.truncated { truncatedSections.append(String(localized: "Description")) }

        var instructions: [String] = []
        for item in includedInstructions.prefix(PrintContentBudget.maximumSections) {
            let result = budget.consume(item.instructions)
            instructions.append(result.text)
            if result.truncated, !truncatedSections.contains("Candidate Instructions") {
                truncatedSections.append(String(localized: "Candidate Instructions"))
            }
        }
        printableInstructions = instructions

        let contents = budget.consume(question.contents ?? "")
        printableContents = contents.text
        if contents.truncated { truncatedSections.append(String(localized: "Starter Code")) }

        let solution = budget.consume(Self.includedSolution(question.solution, audience: audience))
        printableSolution = solution.text
        if solution.truncated { truncatedSections.append(String(localized: "Solution")) }
        let systemPrompt = budget.consume(
            Self.includedAIAssistSystemPrompt(question.aiAssistCustomSystemPrompt, audience: audience)
        )
        printableAIAssistSystemPrompt = systemPrompt.text
        if systemPrompt.truncated { truncatedSections.append(
            String(localized: "Confidential: AI Assist Custom System Prompt")
        ) }
        truncationSummary = truncatedSections.isEmpty ? nil : truncatedSections.formatted()
    }

    /// Trimmed, so a whitespace-only title falls back to the placeholder instead of
    /// printing a blank heading (#1950).
    private var displayTitle: String {
        let trimmed = question.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return Self.boundedLabel(trimmed.isEmpty ? String(localized: "Untitled Question") : trimmed)
    }

    /// Whether any printable section will render, so an all-empty question gets an
    /// explicit note rather than a bare title over blank paper (#1956).
    private var hasPrintableContent: Bool {
        !printableDescription.isEmpty
            || printableInstructions.contains(where: { !$0.isEmpty })
            || !printableContents.isEmpty
            || !printableSolution.isEmpty
            || !printableAIAssistSystemPrompt.isEmpty
    }

    private var metaLine: String {
        var parts: [String] = [question.interviewType.label]
        if let language = question.language, !language.isEmpty {
            parts.append(language.coderPadLanguageDisplayName)
        }
        if let author = question.authorName, !author.isEmpty {
            parts.append(String(localized: "by \(author)"))
        }
        return PrintContentBudget.boundedLabel(parts.joined(separator: " · "), maximumCharacters: 2048)
    }

    private static func boundedLabel(_ value: String) -> String {
        PrintContentBudget.boundedLabel(value)
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

            if let truncationSummary { truncationNotice(truncationSummary) }

            if !printableDescription.isEmpty {
                PrintableView.PrintSection(title: "Description") {
                    MarkdownText(printableDescription).font(.callout)
                }
            }

            if printableInstructions.contains(where: { !$0.isEmpty }) {
                PrintableView.PrintSection(title: "Candidate Instructions") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(printableInstructions.enumerated()), id: \.offset) { index, instructions in
                            if printableInstructions.count > 1 {
                                Text("Part \(index + 1)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            MarkdownText(instructions).font(.callout)
                        }
                    }
                }
            }
            if !printableContents.isEmpty {
                PrintableView.PrintSection(title: "Starter Code") {
                    PrintableView.PrintCode(code: printableContents)
                }
            }

            if !printableSolution.isEmpty {
                PrintableView.PrintSection(title: "Solution") {
                    MarkdownText(printableSolution).font(.callout)
                }
            }
            if !printableAIAssistSystemPrompt.isEmpty {
                PrintableView.PrintSection(title: "Confidential: AI Assist Custom System Prompt") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Interviewer only. Appended after CoderPad's base AI Assist system prompt.")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(verbatim: printableAIAssistSystemPrompt).font(.callout.monospaced())
                    }
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

    private func truncationNotice(_ sections: String) -> some View {
        Text("Content was omitted from \(sections) because this document exceeds the safe print limit.")
            .font(.callout)
            .foregroundStyle(.secondary)
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
enum PadSummaryIdentityPolicy: Equatable {
    case redact
    case include
}

func padSummaryRows(
    _ pad: Pad,
    identityPolicy: PadSummaryIdentityPolicy = .redact,
    displayName: (String) -> String = \.self
) -> [(String, String)] {
    var rows: [(String, String)] = [
        ("Type", pad.interviewType?.label ?? "None"),
        ("State", pad.status.label),
        ("Owner", identityPolicy == .include ? displayName(pad.ownerEmail) : "Hidden")
    ]
    if let language = pad.language, !language.isEmpty {
        rows.append(("Language", language.coderPadLanguageDisplayName))
    }
    if !pad.participants.isEmpty {
        // The API can repeat a participant across sessions; a printed summary should
        // name each person once (#1955).
        var seen = Set<String>()
        let unique = pad.participants.filter { seen.insert($0.lowercased()).inserted }
        if identityPolicy == .include {
            let maximumNames = 10
            var value = unique.prefix(maximumNames).map(displayName).joined(separator: ", ")
            if unique.count > maximumNames {
                value += " and \(unique.count - maximumNames) more"
            }
            rows.append(("Participants", value))
        } else {
            rows.append(("Participants", "\(unique.count) hidden"))
        }
    }
    if let createdAt = pad.createdAt {
        rows.append(("Created", createdAt.formatted(date: .long, time: .shortened)))
    }
    if let endedAt = pad.endedAt {
        rows.append((String(localized: "Ended"), endedAt.formatted(date: .long, time: .shortened)))
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

    /// Derived once, in `init`, from inputs that cannot change for a given instance.
    ///
    /// Both were computed properties read by `body`, and `body` is evaluated several
    /// times per render by SwiftUI and again by `ImageRenderer` when rasterizing for
    /// print — so building the summary rows (allocating arrays, de-duplicating
    /// participants through a set, formatting dates) and remapping every file for
    /// unique ids and disambiguated headings all re-ran each time (#2220, #2221).
    private let summaryRows: [(String, String)]
    private let displayFiles: [PadPrintFile]
    private let truncationSummary: String?

    init(
        pad: Pad,
        files: [PadPrintFile],
        identityPolicy: PadSummaryIdentityPolicy = .redact,
        displayName: @escaping (String) -> String = \.self
    ) {
        self.pad = pad
        self.files = files
        self.displayName = displayName
        summaryRows = padSummaryRows(pad, identityPolicy: identityPolicy, displayName: displayName).map {
            (PrintContentBudget.boundedLabel($0.0),
             PrintContentBudget.boundedLabel($0.1, maximumCharacters: 2048))
        }
        var budget = PrintContentBudget()
        var boundedFiles: [PadPrintFile] = []
        var truncatedSections: [String] = files.count > PrintContentBudget.maximumFiles
            ? [String(localized: "additional files")] : []
        for file in files.prefix(PrintContentBudget.maximumFiles) {
            let code = budget.consume(file.code)
            boundedFiles.append(PadPrintFile(id: file.id,
                                             title: PrintContentBudget.boundedLabel(file.title), code: code.text,
                                             language: file.language))
            if code.truncated { truncatedSections.append(file.title) }
        }
        displayFiles = Self.disambiguated(boundedFiles)
        truncationSummary = truncatedSections.isEmpty ? nil : truncatedSections.formatted()
    }

    /// Trimmed, so a whitespace-only title falls back to the pad id instead of a
    /// blank heading (#1951).
    private var displayTitle: String {
        let trimmed = pad.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return PrintContentBudget.boundedLabel(trimmed.isEmpty ? pad.id : trimmed)
    }

    /// Files with guaranteed-unique SwiftUI identities and disambiguated headings:
    /// file ids come from the server and can repeat (#1952), and two files can share
    /// one display name, which would make their printed sections indistinguishable
    /// (#1953).
    private static func disambiguated(_ files: [PadPrintFile]) -> [PadPrintFile] {
        var seenIDs: Set<String> = []
        var titleCounts: [String: Int] = [:]
        for file in files {
            titleCounts[file.title, default: 0] += 1
        }
        var titleOrdinals: [String: Int] = [:]
        return files.map { file in
            var id = file.id
            while !seenIDs.insert(id).inserted {
                id += "+"
            }
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

            if let truncationSummary {
                Text(
                    "Content was omitted from \(truncationSummary) because this document exceeds the safe print limit."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            ForEach(displayFiles) { file in
                PrintableView.PrintSection(title: file.title) { PrintableView.PrintCode(code: file.code) }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
