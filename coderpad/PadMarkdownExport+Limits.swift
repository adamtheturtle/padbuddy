//
//  PadMarkdownExport+Limits.swift
//  coderpad
//

import Foundation

enum MarkdownExportLimits {
    static let inlineCharacters = 500
    static let proseCharacters = 100_000
    static let codeCharacters = 250_000
    static let summaryRows = 30
    static let padFiles = 20
    static let instructions = 20
    static let testCases = 1000
    static let customFiles = 1000
}

func boundedMarkdownExportText(_ text: String, maximumCharacters: Int) -> (text: String, omitted: Bool) {
    let prefix = text.prefix(maximumCharacters)
    return (String(prefix), prefix.endIndex != text.endIndex)
}

func markdownExportInline(_ text: String) -> String {
    let bounded = boundedMarkdownExportText(text, maximumCharacters: MarkdownExportLimits.inlineCharacters)
    return markdownInlineEscaped(bounded.text + (bounded.omitted ? "…" : ""))
}

func boundedMarkdownTestCaseInput(_ arguments: [String]?) -> String {
    guard let arguments, !arguments.isEmpty else { return "None" }

    let maximumCharacters = 1000
    var result = ""
    var omitted = false
    for (index, argument) in arguments.enumerated() {
        if !result.isEmpty {
            guard result.count + 2 < maximumCharacters else {
                omitted = true
                break
            }

            result.append(", ")
        }
        let remaining = maximumCharacters - result.count
        guard remaining > 0 else {
            omitted = true
            break
        }

        let prefix = argument.prefix(remaining)
        result.append(contentsOf: prefix)
        if prefix.endIndex != argument.endIndex
            || (result.count >= maximumCharacters && index < arguments.index(before: arguments.endIndex)) {
            omitted = true
        }
        if result.count >= maximumCharacters { break }
    }
    if omitted { result.append("…") }
    return result
}
