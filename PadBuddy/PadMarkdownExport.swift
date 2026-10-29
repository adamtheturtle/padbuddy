//
//  PadMarkdownExport.swift
//  coderpad
//
//  Builds a Markdown document for a pad — title, a summary list, and one fenced code
//  block per file (#524). Kept as pure string assembly (no AppKit, no model decoding)
//  so it's unit-tested directly; PadDetailView supplies the title, summary rows, and
//  files, and writes the result to disk via a save panel.
//

// swiftlint:disable file_length

import Foundation
import SwiftUI

/// Assembles the Markdown for a pad: an H1 title, a bullet-list summary, and a
/// language-tagged fenced code block per file. The fences are sized to be longer than
/// any backtick run in the code, so code that itself contains ``` doesn't break out.
func padMarkdownDocument(
    title: String,
    summary: [(String, String)],
    files: [PadPrintFile],
    sourceURL: URL? = nil,
    generatedAt: Date = Date()
) -> String {
    let heading = String(title.prefix(MarkdownExportLimits.inlineCharacters))
        .trimmingCharacters(in: .whitespacesAndNewlines)
    var lines: [String] = [
        "# \(markdownExportInline(heading.isEmpty ? String(localized: "Untitled Pad") : heading))",
        "",
        "\(String(localized: "Generated")): \(generatedAt.formatted(.iso8601))",
        ""
    ]
    if let sourceURL {
        lines += ["\(String(localized: "Source")): <\(sourceURL.absoluteString)>", ""]
    }

    appendSummary(summary, to: &lines)

    // Disambiguated, as the print document already does. `printFiles()` titles each file
    // with its bare path, and a pad with more than one environment carries two files named
    // `main.py` — so the export emitted two identical `## main.py` headings with different
    // code under each and nothing saying which was which (#4747).
    for file in disambiguatedMarkdownFiles(files).prefix(MarkdownExportLimits.padFiles) {
        appendCodeSection(title: file.title, code: file.code, language: file.language, to: &lines)
    }
    appendOmission(files.count - MarkdownExportLimits.padFiles, kind: .padFiles, to: &lines)

    return finalizedMarkdown(lines)
}

enum QuestionDocumentAudience: Equatable {
    case candidate
    case interviewer
}

func questionMarkdownDocument(
    _ question: Question,
    audience: QuestionDocumentAudience = .candidate,
    sourceURL: URL? = nil,
    generatedAt: Date = Date(),
    displayName: (String) -> String = \.self
) -> String {
    let heading = String(question.title.prefix(MarkdownExportLimits.inlineCharacters))
        .trimmingCharacters(in: .whitespacesAndNewlines)
    var lines: [String] = [
        "# \(markdownExportInline(heading.isEmpty ? String(localized: "Untitled Question") : heading))",
        "",
        "\(String(localized: "Generated")): \(generatedAt.formatted(.iso8601))",
        ""
    ]
    if let sourceURL {
        lines += ["\(String(localized: "Source")): <\(sourceURL.absoluteString)>", ""]
    }

    appendSummary(questionSummaryRows(question, displayName: displayName), to: &lines)
    appendMarkdownSection(title: String(localized: "Description"), text: question.description, to: &lines)
    appendInstructions(question.candidateInstructions, includeHidden: audience == .interviewer, to: &lines)
    appendTestCases(question.testCases, to: &lines)
    appendFiles(question.customFiles, to: &lines)
    if let contents = question.contents, !contents.isEmpty {
        appendCodeSection(title: .init(localized: "Starter Code"), code: contents,
                          language: question.language, to: &lines)
    }
    if let contents = question.contentsForTestCases, !contents.isEmpty, contents != question.contents {
        appendCodeSection(title: .init(localized: "Starter Code (Test Cases)"), code: contents,
                          language: question.language, to: &lines)
    }
    if audience == .interviewer {
        appendMarkdownSection(title: String(localized: "Solution"), text: question.solution, to: &lines)
    }
    if audience == .interviewer, let prompt = question.aiAssistCustomSystemPrompt,
       !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        appendMarkdownSection(
            title: String(localized: "Confidential: AI Assist Custom System Prompt"),
            text: prompt,
            to: &lines
        )
    }

    return finalizedMarkdown(lines)
}

func questionSummaryRows(_ question: Question, displayName: (String) -> String = \.self) -> [(String, String)] {
    var rows: [(String, String)] = [(String(localized: "Type"), question.interviewType.label)]
    if let language = question.language, !language.isEmpty {
        rows.append((String(localized: "Language"), language.coderPadLanguageDisplayName))
    }
    if !question.ownerEmail.isEmpty {
        rows.append((String(localized: "Owner"), displayName(question.ownerEmail)))
    }
    if let used = question.used {
        rows.append((String(localized: "Times used"), "\(used)"))
    }
    if question.shared == true {
        rows.append((String(localized: "Shared"), String(localized: "Yes")))
    }
    if question.testCasesEnabled == true {
        rows.append((String(localized: "Test cases"), String(localized: "Enabled")))
    }
    if question.isDraft == true {
        rows.append((String(localized: "Draft"), String(localized: "Yes")))
    }
    if question.publicTakeHomeSettingID != nil {
        rows.append((String(localized: "Public link"), String(localized: "Configured")))
    }
    if let createdAt = question.createdAt {
        rows.append((String(localized: "Created"), createdAt.formatted(date: .long, time: .omitted)))
    }
    if let updatedAt = question.updatedAt {
        rows.append((String(localized: "Updated"), updatedAt.formatted(date: .long, time: .omitted)))
    }
    return rows
}

private func appendSummary(_ summary: [(String, String)], to lines: inout [String]) {
    for (label, value) in summary.prefix(MarkdownExportLimits.summaryRows) {
        lines.append("- **\(markdownExportInline(label)):** \(markdownExportInline(value))")
    }
    appendOmission(summary.count - MarkdownExportLimits.summaryRows, kind: .summaryRows, to: &lines)
    if !summary.isEmpty {
        lines.append("")
    }
}

private func appendMarkdownSection(title: String, text: String?, to lines: inout [String]) {
    guard let text, !text.isEmpty else { return }

    lines.append("## \(markdownInlineEscaped(title))")
    lines.append("")
    lines += isolatedMarkdownBody(text)
    lines.append("")
}

/// Remote prose keeps its authored Markdown emphasis/links, but remains inside an
/// app-owned blockquote so headings, lists, and thematic rules cannot restructure
/// the export. Raw HTML is entity-escaped rather than executed by renderers.
func isolatedMarkdownBody(_ text: String) -> [String] {
    let bounded = boundedMarkdownExportText(text, maximumCharacters: MarkdownExportLimits.proseCharacters)
    var normalized = bounded.text
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
    if bounded.omitted {
        normalized += "\n\n_\(String(localized: "Content truncated for export."))_"
    }
    return normalized.components(separatedBy: "\n").map { $0.isEmpty ? ">" : "> \($0)" }
}

private func appendCodeSection(title: String, code: String, language: String?, to lines: inout [String]) {
    let bounded = boundedMarkdownExportText(code, maximumCharacters: MarkdownExportLimits.codeCharacters)
    let truncationMarker = bounded.omitted ? "\n// \(String(localized: "Content truncated for export."))" : ""
    let code = bounded.text + truncationMarker
    lines.append("## \(markdownExportInline(title))")
    lines.append("")
    if let fence = codeFence(for: code) {
        lines.append(fence + codeFenceLanguage(language))
        lines.append(code)
        lines.append(fence)
    } else {
        // Both legal fence delimiters have pathological runs. An indented block is
        // equally valid Markdown and has fixed overhead per line (#1545).
        lines += code.components(separatedBy: "\n").map { "    \($0)" }
    }
    lines.append("")
}

private func appendInstructions(
    _ instructions: [CandidateInstruction], includeHidden: Bool, to lines: inout [String]
) {
    let instructions = includeHidden ? instructions : instructions.filter(\.defaultVisible)
    guard !instructions.isEmpty else { return }

    lines.append("## \(String(localized: "Candidate Instructions"))")
    lines.append("")
    for (index, item) in instructions.prefix(MarkdownExportLimits.instructions).enumerated() {
        if instructions.count > 1 || item.name?.isEmpty == false {
            lines.append("### \(markdownExportInline(QuestionInstructionNames.title(item, index: index)))")
            lines.append("")
        }
        if !item.defaultVisible {
            lines.append("> \(String(localized: "Hidden by default"))")
            lines.append("")
        }
        lines += isolatedMarkdownBody(item.instructions)
        lines.append("")
    }
    appendOmission(instructions.count - MarkdownExportLimits.instructions, kind: .instructionParts, to: &lines)
}

private func appendTestCases(_ testCases: [QuestionTestCase], to lines: inout [String]) {
    guard !testCases.isEmpty else { return }

    lines.append("## \(String(localized: "Test Cases"))")
    lines.append("")
    lines.append("| \(String(localized: "Input")) | \(String(localized: "Expected")) |"
        + " \(String(localized: "Visibility")) |")
    lines.append("| --- | --- | --- |")
    for testCase in testCases.prefix(MarkdownExportLimits.testCases) {
        let input = boundedMarkdownTestCaseInput(testCase.arguments)
        let expected = testCase.returnValue ?? String(localized: "None")
        let visibility = testCase.visible == false ? String(localized: "Hidden") : String(localized: "Visible")
        lines.append("| \(markdownTableCell(input)) | \(markdownTableCell(expected)) | \(visibility) |")
    }
    appendOmission(testCases.count - MarkdownExportLimits.testCases, kind: .testCases, to: &lines)
    lines.append("")
}

private func appendFiles(_ files: [QuestionCustomFile], to lines: inout [String]) {
    guard !files.isEmpty else { return }

    lines.append("## \(String(localized: "Files"))")
    lines.append("")
    for file in files.prefix(MarkdownExportLimits.customFiles) {
        var line = "- \(markdownExportInline(questionFileName(file)))"
        if let size = file.filesize, !size.isEmpty {
            line += " (\(markdownExportInline(size)))"
        }
        if let description = file.description, !description.isEmpty {
            line += ": \(markdownExportInline(description))"
        }
        lines.append(line)
    }
    appendOmission(files.count - MarkdownExportLimits.customFiles, kind: .files, to: &lines)
    lines.append("")
}

private enum MarkdownOmissionKind {
    case padFiles
    case summaryRows
    case instructionParts
    case testCases
    case files

    func message(count: Int) -> String {
        switch (self, count == 1) {
        case (.padFiles, true): String(localized: "1 additional pad file omitted from this export.")
        case (.padFiles, false): String(localized: "\(count) additional pad files omitted from this export.")
        case (.summaryRows, true): String(localized: "1 additional summary row omitted from this export.")
        case (.summaryRows, false): String(localized: "\(count) additional summary rows omitted from this export.")
        case (.instructionParts, true): String(localized: "1 additional instruction part omitted from this export.")
        case (.instructionParts, false):
            String(localized: "\(count) additional instruction parts omitted from this export.")
        case (.testCases, true): String(localized: "1 additional test case omitted from this export.")
        case (.testCases, false): String(localized: "\(count) additional test cases omitted from this export.")
        case (.files, true): String(localized: "1 additional file omitted from this export.")
        case (.files, false): String(localized: "\(count) additional files omitted from this export.")
        }
    }
}

private func appendOmission(_ count: Int, kind: MarkdownOmissionKind, to lines: inout [String]) {
    guard count > 0 else { return }

    lines.append("_\(kind.message(count: count))_")
}

private func questionFileName(_ file: QuestionCustomFile) -> String {
    if let filename = file.filename, !filename.isEmpty {
        return filename
    }
    if let title = file.title, !title.isEmpty {
        return title
    }
    return String(localized: "Untitled file")
}

private func finalizedMarkdown(_ lines: [String]) -> String {
    var lines = lines
    while lines.last?.isEmpty == true {
        lines.removeLast()
    }
    return lines.joined(separator: "\n") + "\n"
}

/// Backslash-escapes the characters that carry inline Markdown meaning, so a title,
/// owner name, or language renders literally rather than turning into emphasis, a link,
/// or code.
/// The characters an inline span has to escape. Hoisted out of the function: it runs
/// for every summary label and value, every title, every test-case cell, and every
/// file name in a document, and rebuilt this identical set each time (#2217).
private let markdownInlineSpecials: Set<Character> = ["\\", "`", "*", "_", "[", "]", "<", ">", "|"]

/// A bounded, single-line table value. Remote test data can be arbitrarily large;
/// keeping the first 1,000 graphemes makes the export useful without allowing one
/// argument or expected value to dominate memory and layout (#1547).
func markdownTableCell(_ text: String) -> String {
    let maximumCharacters = 1000
    let prefix = text.prefix(maximumCharacters)
    let wasTruncated = prefix.endIndex != text.endIndex
    var normalized = ""
    normalized.reserveCapacity(min(prefix.utf8.count, maximumCharacters))
    var previousWasWhitespace = false
    for character in prefix {
        if character.isWhitespace {
            if !previousWasWhitespace {
                normalized.append(" ")
            }
            previousWasWhitespace = true
        } else {
            normalized.append(character)
            previousWasWhitespace = false
        }
    }
    if wasTruncated {
        normalized.append("…")
    }
    return markdownInlineEscaped(normalized)
}

func markdownInlineEscaped(_ text: String) -> String {
    // One pass. This used to walk the string for `reserveCapacity`, then three more
    // times through sequential `replacingOccurrences` calls — each allocating another
    // String — before the escaping loop, and it runs once per summary row and per file
    // in an export (#2216). Newline normalization folds into the same loop: Swift's
    // Character already treats CRLF as one grapheme, so it needs no separate pass.
    var result = ""
    result.reserveCapacity(text.count)
    for character in text {
        if character.isNewline {
            result.append(" ")
        } else {
            if markdownInlineSpecials.contains(character) {
                result.append("\\")
            }
            result.append(character)
        }
    }
    return result
}

/// A safe inline Markdown link for clipboard/menu actions. Angle-bracketed link
/// destinations keep URL punctuation from terminating the destination early.
func markdownLink(title: String, url: URL) -> String {
    "[\(markdownInlineEscaped(title))](<\(url.absoluteString)>)"
}

/// A bounded CommonMark fence. Backticks remain the normal output; tildes avoid a
/// large backtick fence. If both need more than 64 characters the caller uses an
/// indented block, preventing remote code from driving an unbounded allocation.
private func codeFence(for code: String) -> String? {
    let maximumFenceLength = 64
    let backticks = longestRun(of: Character("`"), in: code, cappedAt: maximumFenceLength)
    let tildes = longestRun(of: Character("~"), in: code, cappedAt: maximumFenceLength)
    let backtickLength = max(3, backticks + 1)
    let tildeLength = max(3, tildes + 1)

    if backtickLength <= tildeLength, backtickLength <= maximumFenceLength {
        return String(repeating: "`", count: backtickLength)
    }
    if tildeLength <= maximumFenceLength {
        return String(repeating: "~", count: tildeLength)
    }
    return nil
}

private func longestRun(of delimiter: Character, in code: String, cappedAt cap: Int) -> Int {
    var longest = 0
    var current = 0
    for character in code {
        if character == delimiter {
            current = min(cap, current + 1)
            longest = max(longest, current)
        } else {
            current = 0
        }
    }
    return longest
}

/// The fence info string for a language, normalized to a lowercase token (dropping the
/// `multifile_` prefix CoderPad uses for project environments). Empty when unknown, so
/// the fence is a bare ``` rather than ```\n.
private func codeFenceLanguage(_ language: String?) -> String {
    guard var lowered = language?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
          !lowered.isEmpty
    else { return "" }

    if lowered.hasPrefix("multifile_") {
        lowered = String(lowered.dropFirst("multifile_".count))
    }
    // A fence info string is a single token of safe characters. The language is
    // remote content: a newline or backtick in it would escape the fence line and
    // rewrite the exported document's structure, so keep only the leading run of
    // token-safe characters (#1161).
    let token = lowered.prefix { character in
        character.isLetter || character.isNumber
            || character == "-" || character == "_" || character == "+"
            || character == "#" || character == "."
    }
    return String(token)
}

extension FocusedValues {
    /// Published by a detail pane that can export itself as Markdown (#524), so the File ▸
    /// Export as Markdown… command performs it and disables when nothing focused is
    /// exportable. Reuses `PrintAction` (a stable-id + perform closure).
    @Entry var exportMarkdownAction: PrintAction?
}

/// Appends `(1)`, `(2)` to repeated file titles so each exported code section names the
/// file it holds. Shares the print document's rule so the two outputs agree (#4747).
func disambiguatedMarkdownFiles(_ files: [PadPrintFile]) -> [PadPrintFile] {
    var titleCounts: [String: Int] = [:]
    for file in files {
        titleCounts[file.title, default: 0] += 1
    }
    var titleOrdinals: [String: Int] = [:]
    return files.map { file in
        guard titleCounts[file.title, default: 0] > 1 else { return file }

        let ordinal = (titleOrdinals[file.title] ?? 0) + 1
        titleOrdinals[file.title] = ordinal
        return PadPrintFile(
            id: file.id, title: "\(file.title) (\(ordinal))", code: file.code, language: file.language
        )
    }
}
