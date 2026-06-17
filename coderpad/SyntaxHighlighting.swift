//
//  SyntaxHighlighting.swift
//  coderpad
//

import AppKit
import Highlightr
import SwiftUI

/// Colourises the code preview in the pad detail view.
///
/// The primary engine is **Highlightr** (highlight.js), which gives accurate,
/// language-aware highlighting across ~190 languages. When Highlightr can't
/// help — an unmapped/unknown language or oversized input — we fall back to a
/// small built-in lexer so the preview never regresses to plain text
/// unexpectedly.
@MainActor
enum SyntaxHighlighter {
    /// Source longer than this is rendered without highlighting to keep the
    /// detail pane responsive — highlighting very large inputs isn't worth the
    /// cost for a preview.
    private static let maxLength = 40000

    /// Colours for the fallback lexer, chosen to read in light and dark.
    private enum Palette {
        static let keyword = Color(red: 0.82, green: 0.36, blue: 0.60)
        static let type = Color(red: 0.27, green: 0.66, blue: 0.71)
        static let string = Color(red: 0.84, green: 0.43, blue: 0.36)
        static let number = Color(red: 0.36, green: 0.55, blue: 0.86)
        static let comment = Color(red: 0.46, green: 0.60, blue: 0.46)
    }

    /// Returns an attributed copy of `source` with token colours applied.
    /// Callers keep applying their own monospaced font; only foreground
    /// colours are set here. `dark` selects a theme suited to the current
    /// appearance.
    static func highlight(_ source: String, language: String?, dark: Bool) -> AttributedString {
        guard source.count <= maxLength else { return AttributedString(source) }

        // Plain text shouldn't be coloured at all.
        if HighlightrEngine.isPlainText(language) { return AttributedString(source) }
        if let highlighted = HighlightrEngine.shared.highlight(source, language: language, dark: dark) {
            return highlighted
        }
        return lexerHighlight(source, language: language)
    }

    /// A syntax-highlighted RTF representation of `source`, for copying code to the
    /// pasteboard so it pastes into Pages/Mail/docs with its colours intact. `nil`
    /// for plain text, unmapped languages, or oversized input, so the caller falls
    /// back to copying plain text only.
    static func rtf(_ source: String, language: String?, dark: Bool) -> Data? {
        guard source.count <= maxLength, !HighlightrEngine.isPlainText(language) else { return nil }

        return HighlightrEngine.shared.rtf(source, language: language, dark: dark)
    }

    /// Single-pass fallback lexer (comments, strings, numbers, keywords) tuned
    /// per language family. Used only when Highlightr declines a language.
    private static func lexerHighlight(_ source: String, language: String?) -> AttributedString {
        let syntax = LanguageSyntax.forLanguage(language)
        let builder = TokenBuilder(chars: Array(source))

        while builder.index < builder.count {
            if scanComment(builder, syntax: syntax) { continue }
            if scanString(builder, syntax: syntax) { continue }
            if scanNumber(builder) { continue }
            if scanIdentifier(builder, syntax: syntax) { continue }
            builder.index += 1
        }

        return builder.finish()
    }

    /// Accumulates coloured pieces while a cursor walks the character array.
    private final class TokenBuilder {
        let chars: [Character]
        let count: Int
        var index = 0
        private var output = AttributedString()
        private var plainStart = 0

        init(chars: [Character]) {
            self.chars = chars
            count = chars.count
        }

        private func flushPlain(upTo end: Int) {
            if end > plainStart {
                output.append(AttributedString(String(chars[plainStart ..< end])))
            }
        }

        func emit(from start: Int, to end: Int, color: Color) {
            flushPlain(upTo: start)
            var piece = AttributedString(String(chars[start ..< end]))
            piece.foregroundColor = color
            output.append(piece)
            plainStart = end
        }

        func matches(_ token: [Character], at pos: Int) -> Bool {
            guard pos + token.count <= count else { return false }

            for offset in 0 ..< token.count where chars[pos + offset] != token[offset] {
                return false
            }
            return true
        }

        func finish() -> AttributedString {
            flushPlain(upTo: count)
            return output
        }
    }

    /// Block comments (e.g. `/* ... */`) and line comments (e.g. `//`, `#`).
    private static func scanComment(_ builder: TokenBuilder, syntax: LanguageSyntax) -> Bool {
        let start = builder.index
        for block in syntax.blockComments where builder.matches(block.open, at: start) {
            var end = start + block.open.count
            while end < builder.count, !builder.matches(block.close, at: end) {
                end += 1
            }
            end = end < builder.count ? end + block.close.count : builder.count
            builder.emit(from: start, to: end, color: Palette.comment)
            builder.index = end
            return true
        }
        for marker in syntax.lineComments where builder.matches(marker, at: start) {
            var end = start
            while end < builder.count, builder.chars[end] != "\n" {
                end += 1
            }
            builder.emit(from: start, to: end, color: Palette.comment)
            builder.index = end
            return true
        }
        return false
    }

    /// String literals. Delimiters are sorted longest-first so triple quotes
    /// win over single quotes.
    private static func scanString(_ builder: TokenBuilder, syntax: LanguageSyntax) -> Bool {
        let start = builder.index
        for delim in syntax.stringDelimiters where builder.matches(delim, at: start) {
            let len = delim.count
            var end = start + len
            while end < builder.count {
                if syntax.escapesWithBackslash, builder.chars[end] == "\\", end + 1 < builder.count {
                    end += 2
                    continue
                }
                if builder.matches(delim, at: end) {
                    end += len
                    break
                }
                // A single-character delimiter doesn't span lines.
                if len == 1, builder.chars[end] == "\n" { break }
                end += 1
            }
            end = min(end, builder.count)
            builder.emit(from: start, to: end, color: Palette.string)
            builder.index = end
            return true
        }
        return false
    }

    /// Numeric literals (including hex/binary/float forms).
    private static func scanNumber(_ builder: TokenBuilder) -> Bool {
        let start = builder.index
        let chars = builder.chars
        let count = builder.count
        let character = chars[start]
        let startsNumber = character.isNumber
            || (character == "." && start + 1 < count && chars[start + 1].isNumber)
        guard startsNumber else { return false }

        let prevIsIdentifier = start > 0 && (chars[start - 1].isLetter || chars[start - 1] == "_")
        guard !prevIsIdentifier else { return false }

        var end = start
        // Detect a radix prefix (0x / 0b / 0o) so we only accept digits valid
        // for that base and stop at the first identifier character, rather than
        // greedily eating trailing letters (e.g. `123abc`).
        var isHexLiteral = false
        if chars[end] == "0", end + 1 < count {
            switch chars[end + 1] {
            case "x", "X": isHexLiteral = true; end += 2
            case "b", "B", "o", "O": end += 2
            default: break
            }
        }
        while end < count {
            let digit = chars[end]
            let isDigit = isHexLiteral ? digit.isHexDigit : digit.isNumber
            if isDigit || digit == "_" || digit == "." {
                end += 1
            } else if !isHexLiteral, digit == "e" || digit == "E",
                      end + 1 < count,
                      chars[end + 1].isNumber || chars[end + 1] == "+" || chars[end + 1] == "-" {
                // Decimal exponent, optionally signed.
                end += 2
            } else {
                break
            }
        }
        builder.emit(from: start, to: end, color: Palette.number)
        builder.index = end
        return true
    }

    /// Identifiers: colour only if they are keywords or known types.
    private static func scanIdentifier(_ builder: TokenBuilder, syntax: LanguageSyntax) -> Bool {
        let start = builder.index
        let chars = builder.chars
        let count = builder.count
        let character = chars[start]
        guard character.isLetter || character == "_" else { return false }

        var end = start
        while end < count, chars[end].isLetter || chars[end].isNumber || chars[end] == "_" {
            end += 1
        }
        let word = String(chars[start ..< end])
        let lookup = syntax.caseInsensitiveKeywords ? word.lowercased() : word
        if syntax.keywords.contains(lookup) {
            builder.emit(from: start, to: end, color: Palette.keyword)
        } else if syntax.types.contains(word) {
            builder.emit(from: start, to: end, color: Palette.type)
        }
        builder.index = end
        return true
    }
}

/// Wraps a cached ``Highlightr`` instance. The engine loads a JavaScript
/// runtime on init, so we keep one around and only swap the theme when the
/// appearance changes. Confined to the main actor since SwiftUI evaluates the
/// preview's `body` there.
@MainActor
private final class HighlightrEngine {
    static let shared = HighlightrEngine()

    private let highlightr = Highlightr()
    private var currentTheme: String?

    /// Highlights `source`, returning a foreground-coloured attributed string,
    /// or `nil` when the language is unmapped or Highlightr can't parse it (so
    /// the caller can fall back to the built-in lexer).
    func highlight(_ source: String, language: String?, dark: Bool) -> AttributedString? {
        guard let highlightr, let hljsName = Self.highlightJSName(for: language) else { return nil }

        let themeName = dark ? "atom-one-dark" : "xcode"
        if currentTheme != themeName {
            _ = highlightr.setTheme(to: themeName)
            currentTheme = themeName
        }

        guard let rendered = highlightr.highlight(source, as: hljsName, fastRender: true) else { return nil }

        return Self.foregroundOnly(rendered)
    }

    /// The Highlightr-coloured `source` serialized to RTF, with a monospaced font
    /// applied across it so the pasted code reads as code. `nil` when the language
    /// is unmapped or Highlightr can't parse it.
    func rtf(_ source: String, language: String?, dark: Bool) -> Data? {
        guard let highlightr, let hljsName = Self.highlightJSName(for: language) else { return nil }

        let themeName = dark ? "atom-one-dark" : "xcode"
        if currentTheme != themeName {
            _ = highlightr.setTheme(to: themeName)
            currentTheme = themeName
        }
        guard let rendered = highlightr.highlight(source, as: hljsName, fastRender: true) else { return nil }

        let mutable = NSMutableAttributedString(attributedString: rendered)
        let full = NSRange(location: 0, length: mutable.length)
        mutable.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), range: full)
        return try? mutable.data(from: full,
                                 documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }

    /// Converts a Highlightr `NSAttributedString` into a SwiftUI
    /// `AttributedString` that carries only foreground colours, so the caller's
    /// monospaced font (and Dynamic Type) keeps applying.
    private static func foregroundOnly(_ attributed: NSAttributedString) -> AttributedString {
        var out = AttributedString()
        let fullRange = NSRange(location: 0, length: attributed.length)
        attributed.enumerateAttribute(.foregroundColor, in: fullRange) { value, range, _ in
            var piece = AttributedString(attributed.attributedSubstring(from: range).string)
            if let color = value as? NSColor {
                piece.foregroundColor = Color(nsColor: color)
            }
            out.append(piece)
        }
        return out
    }

    /// True for languages that should render as plain, uncoloured text.
    static func isPlainText(_ language: String?) -> Bool {
        switch (language ?? "").lowercased() {
        case "plaintext", "plain-text", "plain_text", "text", "": true
        default: false
        }
    }

    /// Maps CoderPad's language codes to highlight.js identifiers. Returns
    /// `nil` for languages Highlightr doesn't cover, deferring to the lexer.
    private static func highlightJSName(for language: String?) -> String? {
        highlightJSNames[(language ?? "").lowercased()]
    }

    /// CoderPad language code to highlight.js identifier. Codes absent here are
    /// unmapped, so the caller falls back to the built-in lexer.
    private static let highlightJSNames: [String: String] = [
        "python": "python", "python2": "python", "python3": "python",
        "javascript": "javascript", "nodejs": "javascript",
        "node": "javascript", "node.js": "javascript",
        "typescript": "typescript",
        "swift": "swift",
        "go": "go", "golang": "go",
        "rust": "rust",
        "java": "java",
        "kotlin": "kotlin",
        "scala": "scala",
        "ruby": "ruby",
        "c": "c",
        "cpp": "cpp", "c++": "cpp",
        "csharp": "csharp", "c#": "csharp",
        "objective-c": "objectivec", "objc": "objectivec",
        "php": "php",
        "r": "r",
        "sql": "sql", "mysql": "sql", "postgresql": "sql", "postgres": "sql",
        "bash": "bash", "shell": "bash", "sh": "bash",
        "elixir": "elixir",
        "erlang": "erlang",
        "haskell": "haskell",
        "perl": "perl",
        "lua": "lua",
        "dart": "dart",
        "clojure": "clojure",
        "ocaml": "ocaml",
        "fsharp": "fsharp", "f#": "fsharp",
        "html": "xml",
        "css": "css"
    ]
}
