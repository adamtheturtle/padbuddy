//
//  PadMarkdownExport.swift
//  coderpad
//
//  Builds a Markdown document for a pad — title, a summary list, and one fenced code
//  block per file (#524). Kept as pure string assembly (no AppKit, no model decoding)
//  so it's unit-tested directly; PadDetailView supplies the title, summary rows, and
//  files, and writes the result to disk via a save panel.
//

import Foundation
import SwiftUI

/// Assembles the Markdown for a pad: an H1 title, a bullet-list summary, and a
/// language-tagged fenced code block per file. The fences are sized to be longer than
/// any backtick run in the code, so code that itself contains ``` doesn't break out.
func padMarkdownDocument(title: String, summary: [(String, String)], files: [PadPrintFile]) -> String {
    let heading = title.trimmingCharacters(in: .whitespacesAndNewlines)
    var lines: [String] = ["# \(markdownInlineEscaped(heading.isEmpty ? "Untitled Pad" : heading))", ""]

    appendSummary(summary, to: &lines)

    for file in files {
        appendCodeSection(title: file.title, code: file.code, language: file.language, to: &lines)
    }

    return finalizedMarkdown(lines)
}

func questionMarkdownDocument(_ question: Question, displayName: (String) -> String = \.self) -> String {
    let heading = question.title.trimmingCharacters(in: .whitespacesAndNewlines)
    var lines: [String] = ["# \(markdownInlineEscaped(heading.isEmpty ? "Untitled Question" : heading))", ""]

    appendSummary(questionSummaryRows(question, displayName: displayName), to: &lines)
    appendMarkdownSection(title: "Description", text: question.description, to: &lines)
    appendInstructions(question.candidateInstructions, to: &lines)
    appendTestCases(question.testCases, to: &lines)
    appendFiles(question.customFiles, to: &lines)

    if let contents = question.contents, !contents.isEmpty {
        appendCodeSection(title: "Starter Code", code: contents, language: question.language, to: &lines)
    }
    if let contents = question.contentsForTestCases, !contents.isEmpty, contents != question.contents {
        appendCodeSection(title: "Starter Code (Test Cases)", code: contents, language: question.language, to: &lines)
    }
    appendMarkdownSection(title: "Solution", text: question.solution, to: &lines)

    return finalizedMarkdown(lines)
}

func questionSummaryRows(_ question: Question, displayName: (String) -> String = \.self) -> [(String, String)] {
    var rows: [(String, String)] = [("Type", question.interviewType.label)]
    if let language = question.language, !language.isEmpty {
        rows.append(("Language", language.coderPadLanguageDisplayName))
    }
    if !question.ownerEmail.isEmpty {
        rows.append(("Owner", displayName(question.ownerEmail)))
    }
    if let used = question.used {
        rows.append(("Times used", "\(used)"))
    }
    if question.shared == true {
        rows.append(("Shared", "Yes"))
    }
    if question.testCasesEnabled == true {
        rows.append(("Test cases", "Enabled"))
    }
    if question.isDraft == true {
        rows.append(("Draft", "Yes"))
    }
    if question.publicTakeHomeSettingID != nil {
        rows.append(("Public link", "Configured"))
    }
    if let createdAt = question.createdAt {
        rows.append(("Created", createdAt.formatted(date: .long, time: .omitted)))
    }
    if let updatedAt = question.updatedAt {
        rows.append(("Updated", updatedAt.formatted(date: .long, time: .omitted)))
    }
    return rows
}

private func appendSummary(_ summary: [(String, String)], to lines: inout [String]) {
    for (label, value) in summary {
        lines.append("- **\(markdownInlineEscaped(label)):** \(markdownInlineEscaped(value))")
    }
    if !summary.isEmpty { lines.append("") }
}

private func appendMarkdownSection(title: String, text: String?, to lines: inout [String]) {
    guard let text, !text.isEmpty else { return }

    lines.append("## \(markdownInlineEscaped(title))")
    lines.append("")
    lines.append(text)
    lines.append("")
}

private func appendCodeSection(title: String, code: String, language: String?, to lines: inout [String]) {
    let fence = codeFence(for: code)
    lines.append("## \(markdownInlineEscaped(title))")
    lines.append("")
    lines.append(fence + codeFenceLanguage(language))
    lines.append(code)
    lines.append(fence)
    lines.append("")
}

private func appendInstructions(_ instructions: [CandidateInstruction], to lines: inout [String]) {
    guard !instructions.isEmpty else { return }

    lines.append("## Candidate Instructions")
    lines.append("")
    for (index, item) in instructions.enumerated() {
        if instructions.count > 1 {
            lines.append("### Part \(index + 1)")
            lines.append("")
        }
        if !item.defaultVisible {
            lines.append("> Hidden by default")
            lines.append("")
        }
        lines.append(item.instructions)
        lines.append("")
    }
}

private func appendTestCases(_ testCases: [QuestionTestCase], to lines: inout [String]) {
    guard !testCases.isEmpty else { return }

    lines.append("## Test Cases")
    lines.append("")
    lines.append("| Input | Expected | Visibility |")
    lines.append("| --- | --- | --- |")
    for testCase in testCases {
        let input = testCase.arguments?.joined(separator: ", ") ?? "None"
        let expected = testCase.returnValue ?? "None"
        let visibility = testCase.visible == false ? "Hidden" : "Visible"
        lines.append("| \(markdownInlineEscaped(input)) | \(markdownInlineEscaped(expected)) | \(visibility) |")
    }
    lines.append("")
}

private func appendFiles(_ files: [QuestionCustomFile], to lines: inout [String]) {
    guard !files.isEmpty else { return }

    lines.append("## Files")
    lines.append("")
    for file in files {
        var line = "- \(markdownInlineEscaped(questionFileName(file)))"
        if let size = file.filesize, !size.isEmpty {
            line += " (\(markdownInlineEscaped(size)))"
        }
        if let description = file.description, !description.isEmpty {
            line += ": \(markdownInlineEscaped(description))"
        }
        lines.append(line)
    }
    lines.append("")
}

private func questionFileName(_ file: QuestionCustomFile) -> String {
    if let filename = file.filename, !filename.isEmpty { return filename }
    if let title = file.title, !title.isEmpty { return title }
    return "Untitled file"
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
func markdownInlineEscaped(_ text: String) -> String {
    var result = ""
    result.reserveCapacity(text.count)
    let special: Set<Character> = ["\\", "`", "*", "_", "[", "]", "<", ">", "|"]
    for character in text {
        if special.contains(character) { result.append("\\") }
        result.append(character)
    }
    return result
}

/// The opening/closing fence for a code block: at least three backticks, and always
/// longer than the longest run of backticks inside the code so the block can't be
/// closed early by the content (a CommonMark requirement).
private func codeFence(for code: String) -> String {
    var longest = 0
    var current = 0
    for character in code {
        if character == "`" {
            current += 1
            longest = max(longest, current)
        } else {
            current = 0
        }
    }
    return String(repeating: "`", count: max(3, longest + 1))
}

/// The fence info string for a language, normalized to a lowercase token (dropping the
/// `multifile_` prefix CoderPad uses for project environments). Empty when unknown, so
/// the fence is a bare ``` rather than ```\n.
private func codeFenceLanguage(_ language: String?) -> String {
    guard var lowered = language?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
          !lowered.isEmpty
    else { return "" }

    if lowered.hasPrefix("multifile_") { lowered = String(lowered.dropFirst("multifile_".count)) }
    // A fence info string is a single token; keep only the leading word.
    return lowered.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) ?? ""
}

extension FocusedValues {
    /// Published by a detail pane that can export itself as Markdown (#524), so the File ▸
    /// Export as Markdown… command performs it and disables when nothing focused is
    /// exportable. Reuses `PrintAction` (a stable-id + perform closure).
    @Entry var exportMarkdownAction: PrintAction?
}
