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

    for (label, value) in summary {
        lines.append("- **\(markdownInlineEscaped(label)):** \(markdownInlineEscaped(value))")
    }
    if !summary.isEmpty { lines.append("") }

    for file in files {
        let fence = codeFence(for: file.code)
        lines.append("## \(markdownInlineEscaped(file.title))")
        lines.append("")
        lines.append(fence + codeFenceLanguage(file.language))
        lines.append(file.code)
        lines.append(fence)
        lines.append("")
    }

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
