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
    lines.append("## \(markdownInlineEscaped(title))")
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
        lines.append("| \(markdownTableCell(input)) | \(markdownTableCell(expected)) | \(visibility) |")
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
            if !previousWasWhitespace { normalized.append(" ") }
            previousWasWhitespace = true
        } else {
            normalized.append(character)
            previousWasWhitespace = false
        }
    }
    if wasTruncated { normalized.append("…") }
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
            if markdownInlineSpecials.contains(character) { result.append("\\") }
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

    if lowered.hasPrefix("multifile_") { lowered = String(lowered.dropFirst("multifile_".count)) }
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
