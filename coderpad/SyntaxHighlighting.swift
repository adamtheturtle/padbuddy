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
    private static let maxLength = 40_000

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

    /// Single-pass fallback lexer (comments, strings, numbers, keywords) tuned
    /// per language family. Used only when Highlightr declines a language.
    private static func lexerHighlight(_ source: String, language: String?) -> AttributedString {
        let syntax = LanguageSyntax.forLanguage(language)
        let chars = Array(source)
        let n = chars.count
        var out = AttributedString()
        var i = 0
        var plainStart = 0

        func flushPlain(upTo end: Int) {
            if end > plainStart {
                out.append(AttributedString(String(chars[plainStart..<end])))
            }
        }
        func emit(from start: Int, to end: Int, color: Color) {
            flushPlain(upTo: start)
            var piece = AttributedString(String(chars[start..<end]))
            piece.foregroundColor = color
            out.append(piece)
            plainStart = end
        }
        func matches(_ token: [Character], at pos: Int) -> Bool {
            guard pos + token.count <= n else { return false }
            for k in 0..<token.count where chars[pos + k] != token[k] { return false }
            return true
        }

        while i < n {
            let c = chars[i]
            var handled = false

            // Block comments (e.g. /* ... */).
            for block in syntax.blockComments where matches(block.open, at: i) {
                var j = i + block.open.count
                while j < n && !matches(block.close, at: j) { j += 1 }
                j = j < n ? j + block.close.count : n
                emit(from: i, to: j, color: Palette.comment)
                i = j
                handled = true
                break
            }
            if handled { continue }

            // Line comments (e.g. // or # or --).
            for marker in syntax.lineComments where matches(marker, at: i) {
                var j = i
                while j < n && chars[j] != "\n" { j += 1 }
                emit(from: i, to: j, color: Palette.comment)
                i = j
                handled = true
                break
            }
            if handled { continue }

            // String literals. Delimiters are sorted longest-first so triple
            // quotes win over single quotes.
            for delim in syntax.stringDelimiters where matches(delim, at: i) {
                let len = delim.count
                var j = i + len
                while j < n {
                    if syntax.escapesWithBackslash && chars[j] == "\\" && j + 1 < n {
                        j += 2
                        continue
                    }
                    if matches(delim, at: j) {
                        j += len
                        break
                    }
                    // A single-character delimiter doesn't span lines.
                    if len == 1 && chars[j] == "\n" { break }
                    j += 1
                }
                j = min(j, n)
                emit(from: i, to: j, color: Palette.string)
                i = j
                handled = true
                break
            }
            if handled { continue }

            // Numeric literals (including hex/binary/float forms).
            if c.isNumber || (c == "." && i + 1 < n && chars[i + 1].isNumber) {
                let prevIsIdentifier = i > 0 && (chars[i - 1].isLetter || chars[i - 1] == "_")
                if !prevIsIdentifier {
                    var j = i
                    // Detect a radix prefix (0x / 0b / 0o) so we only accept digits
                    // valid for that base and stop at the first identifier character,
                    // rather than greedily eating trailing letters (e.g. `123abc`).
                    var isHexLiteral = false
                    if chars[j] == "0", j + 1 < n {
                        switch chars[j + 1] {
                        case "x", "X": isHexLiteral = true; j += 2
                        case "b", "B", "o", "O": j += 2
                        default: break
                        }
                    }
                    while j < n {
                        let d = chars[j]
                        let isDigit = isHexLiteral ? d.isHexDigit : d.isNumber
                        if isDigit || d == "_" || d == "." {
                            j += 1
                        } else if !isHexLiteral && (d == "e" || d == "E")
                                    && j + 1 < n
                                    && (chars[j + 1].isNumber || chars[j + 1] == "+" || chars[j + 1] == "-") {
                            // Decimal exponent, optionally signed.
                            j += 2
                        } else {
                            break
                        }
                    }
                    emit(from: i, to: j, color: Palette.number)
                    i = j
                    continue
                }
            }

            // Identifiers: colour only if they are keywords or known types.
            if c.isLetter || c == "_" {
                var j = i
                while j < n && (chars[j].isLetter || chars[j].isNumber || chars[j] == "_") { j += 1 }
                let word = String(chars[i..<j])
                let lookup = syntax.caseInsensitiveKeywords ? word.lowercased() : word
                if syntax.keywords.contains(lookup) {
                    emit(from: i, to: j, color: Palette.keyword)
                } else if syntax.types.contains(word) {
                    emit(from: i, to: j, color: Palette.type)
                }
                i = j
                continue
            }

            i += 1
        }

        flushPlain(upTo: n)
        return out
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

    /// Converts a Highlightr `NSAttributedString` into a SwiftUI
    /// `AttributedString` that carries only foreground colours, so the caller's
    /// monospaced font (and Dynamic Type) keeps applying.
    private static func foregroundOnly(_ ns: NSAttributedString) -> AttributedString {
        var out = AttributedString()
        let fullRange = NSRange(location: 0, length: ns.length)
        ns.enumerateAttribute(.foregroundColor, in: fullRange) { value, range, _ in
            var piece = AttributedString(ns.attributedSubstring(from: range).string)
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
        case "plaintext", "plain-text", "plain_text", "text", "": return true
        default: return false
        }
    }

    /// Maps CoderPad's language codes to highlight.js identifiers. Returns
    /// `nil` for languages Highlightr doesn't cover, deferring to the lexer.
    private static func highlightJSName(for language: String?) -> String? {
        switch (language ?? "").lowercased() {
        case "python", "python2", "python3": return "python"
        case "javascript", "nodejs", "node", "node.js": return "javascript"
        case "typescript": return "typescript"
        case "swift": return "swift"
        case "go", "golang": return "go"
        case "rust": return "rust"
        case "java": return "java"
        case "kotlin": return "kotlin"
        case "scala": return "scala"
        case "ruby": return "ruby"
        case "c": return "c"
        case "cpp", "c++": return "cpp"
        case "csharp", "c#": return "csharp"
        case "objective-c", "objc": return "objectivec"
        case "php": return "php"
        case "r": return "r"
        case "sql", "mysql", "postgresql", "postgres": return "sql"
        case "bash", "shell", "sh": return "bash"
        case "elixir": return "elixir"
        case "erlang": return "erlang"
        case "haskell": return "haskell"
        case "perl": return "perl"
        case "lua": return "lua"
        case "dart": return "dart"
        case "clojure": return "clojure"
        case "ocaml": return "ocaml"
        case "fsharp", "f#": return "fsharp"
        case "html": return "xml"
        case "css": return "css"
        default: return nil
        }
    }
}

/// Per-language lexing rules. Languages are grouped into families that share
/// comment, string, and keyword conventions.
private struct LanguageSyntax {
    struct BlockComment {
        let open: [Character]
        let close: [Character]
        init(_ open: String, _ close: String) {
            self.open = Array(open)
            self.close = Array(close)
        }
    }

    var keywords: Set<String>
    var types: Set<String>
    var lineComments: [[Character]]
    var blockComments: [BlockComment]
    /// Sorted longest-first by ``forLanguage`` so multi-character delimiters match first.
    var stringDelimiters: [[Character]]
    var escapesWithBackslash: Bool = true
    var caseInsensitiveKeywords: Bool = false

    static func forLanguage(_ language: String?) -> LanguageSyntax {
        let lang = (language ?? "").lowercased()

        var syntax: LanguageSyntax
        switch lang {
        case "python", "python2", "python3":
            syntax = LanguageSyntax(
                keywords: Keywords.python, types: Types.common,
                lineComments: [Array("#")], blockComments: [],
                stringDelimiters: ["\"\"\"", "'''", "\"", "'"].map { Array($0) })

        case "ruby":
            syntax = LanguageSyntax(
                keywords: Keywords.ruby, types: Types.common,
                lineComments: [Array("#")], blockComments: [],
                stringDelimiters: ["\"", "'"].map { Array($0) })

        case "bash", "shell", "sh":
            syntax = LanguageSyntax(
                keywords: Keywords.shell, types: [],
                lineComments: [Array("#")], blockComments: [],
                stringDelimiters: ["\"", "'"].map { Array($0) })

        case "sql", "mysql", "postgresql", "postgres":
            syntax = LanguageSyntax(
                keywords: Keywords.sql, types: [],
                lineComments: [Array("--")], blockComments: [.init("/*", "*/")],
                stringDelimiters: ["'", "\""].map { Array($0) },
                escapesWithBackslash: false, caseInsensitiveKeywords: true)

        case "lua":
            syntax = LanguageSyntax(
                keywords: Keywords.lua, types: [],
                lineComments: [Array("--")], blockComments: [.init("--[[", "]]")],
                stringDelimiters: ["\"", "'"].map { Array($0) })

        case "haskell":
            syntax = LanguageSyntax(
                keywords: Keywords.haskell, types: Types.common,
                lineComments: [Array("--")], blockComments: [.init("{-", "-}")],
                stringDelimiters: ["\""].map { Array($0) })

        case "clojure":
            syntax = LanguageSyntax(
                keywords: Keywords.lisp, types: [],
                lineComments: [Array(";")], blockComments: [],
                stringDelimiters: ["\""].map { Array($0) })

        case "erlang":
            syntax = LanguageSyntax(
                keywords: Keywords.cLike, types: [],
                lineComments: [Array("%")], blockComments: [],
                stringDelimiters: ["\""].map { Array($0) })

        case "ocaml", "fsharp", "f#":
            syntax = LanguageSyntax(
                keywords: Keywords.cLike, types: Types.common,
                lineComments: lang == "ocaml" ? [] : [Array("//")],
                blockComments: [.init("(*", "*)")],
                stringDelimiters: ["\""].map { Array($0) })

        case "html":
            syntax = LanguageSyntax(
                keywords: [], types: [],
                lineComments: [], blockComments: [.init("<!--", "-->")],
                stringDelimiters: ["\"", "'"].map { Array($0) })

        case "css":
            syntax = LanguageSyntax(
                keywords: [], types: [],
                lineComments: [], blockComments: [.init("/*", "*/")],
                stringDelimiters: ["\"", "'"].map { Array($0) })

        case "swift":
            syntax = LanguageSyntax(
                keywords: Keywords.cLike, types: Types.common,
                lineComments: [Array("//")], blockComments: [.init("/*", "*/")],
                stringDelimiters: ["\"\"\"", "\"", "'"].map { Array($0) })

        default:
            // C-family and anything unrecognised.
            syntax = LanguageSyntax(
                keywords: Keywords.cLike, types: Types.common,
                lineComments: [Array("//")], blockComments: [.init("/*", "*/")],
                stringDelimiters: ["\"", "'", "`"].map { Array($0) })
        }

        // Ensure longer delimiters are matched before their prefixes.
        syntax.stringDelimiters.sort { $0.count > $1.count }
        return syntax
    }
}

private enum Keywords {
    /// A broad superset covering the C-family plus common cross-language
    /// control-flow words. Over-inclusiveness is fine for highlighting.
    static let cLike: Set<String> = [
        "if", "else", "for", "while", "do", "switch", "case", "default",
        "break", "continue", "return", "goto", "yield", "await", "async",
        "func", "function", "fn", "def", "class", "struct", "enum", "interface",
        "protocol", "extension", "namespace", "module", "package", "trait",
        "impl", "type", "typealias", "typedef", "associatedtype", "actor",
        "public", "private", "protected", "internal", "fileprivate", "open",
        "static", "final", "const", "let", "var", "val", "new", "delete",
        "abstract", "virtual", "override", "sealed", "partial", "readonly",
        "mutable", "volatile", "register", "inline", "explicit", "friend",
        "try", "catch", "finally", "throw", "throws", "rescue", "ensure",
        "guard", "defer", "where", "lazy", "mutating", "nonmutating", "weak",
        "unowned", "init", "deinit", "get", "set", "willSet", "didSet",
        "import", "include", "using", "from", "as", "in", "is", "of",
        "typeof", "instanceof", "sizeof", "this", "self", "super", "extends",
        "implements", "export", "default", "operator", "macro", "some", "any",
        "true", "false", "null", "nil", "none", "void", "and", "or", "not",
        "match", "loop", "move", "ref", "pub", "use", "mod", "crate", "dyn",
        "with", "lambda", "repeat", "fallthrough", "begin", "end", "then",
    ]

    static let python: Set<String> = [
        "def", "class", "return", "if", "elif", "else", "for", "while",
        "break", "continue", "pass", "import", "from", "as", "with", "try",
        "except", "finally", "raise", "lambda", "yield", "global", "nonlocal",
        "del", "in", "is", "not", "and", "or", "async", "await", "assert",
        "None", "True", "False", "self", "cls", "match", "case",
    ]

    static let ruby: Set<String> = [
        "def", "end", "class", "module", "if", "elsif", "else", "unless",
        "while", "until", "for", "break", "next", "redo", "retry", "return",
        "yield", "do", "begin", "rescue", "ensure", "raise", "then", "case",
        "when", "in", "nil", "true", "false", "self", "super", "require",
        "require_relative", "attr_accessor", "attr_reader", "attr_writer",
        "lambda", "proc", "and", "or", "not", "defined?",
    ]

    static let shell: Set<String> = [
        "if", "then", "else", "elif", "fi", "for", "while", "do", "done",
        "case", "esac", "function", "in", "select", "until", "return",
        "local", "export", "readonly", "declare", "set", "unset", "source",
        "alias", "echo", "exit", "break", "continue",
    ]

    static let sql: Set<String> = [
        "select", "from", "where", "insert", "into", "values", "update",
        "set", "delete", "create", "table", "drop", "alter", "add", "column",
        "primary", "key", "foreign", "references", "index", "view", "join",
        "inner", "left", "right", "outer", "full", "cross", "on", "group",
        "by", "order", "having", "limit", "offset", "union", "all", "distinct",
        "as", "and", "or", "not", "null", "is", "in", "like", "between",
        "case", "when", "then", "else", "end", "exists", "count", "sum",
        "avg", "min", "max", "coalesce", "cast", "convert", "begin", "commit",
        "rollback", "transaction", "with", "returning", "default", "constraint",
        "unique", "check", "asc", "desc", "true", "false",
    ]

    static let lua: Set<String> = [
        "and", "break", "do", "else", "elseif", "end", "false", "for",
        "function", "goto", "if", "in", "local", "nil", "not", "or", "repeat",
        "return", "then", "true", "until", "while",
    ]

    static let haskell: Set<String> = [
        "module", "where", "import", "data", "type", "newtype", "class",
        "instance", "deriving", "do", "let", "in", "if", "then", "else",
        "case", "of", "return", "qualified", "as", "hiding",
    ]

    static let lisp: Set<String> = [
        "def", "defn", "defmacro", "defmulti", "defmethod", "let", "fn",
        "if", "when", "cond", "do", "loop", "recur", "ns", "require",
        "import", "true", "false", "nil", "and", "or", "not", "for", "doseq",
    ]
}

private enum Types {
    /// Common built-in/standard-library type names across languages.
    static let common: Set<String> = [
        "Int", "Int8", "Int16", "Int32", "Int64", "UInt", "UInt8", "UInt16",
        "UInt32", "UInt64", "Double", "Float", "Bool", "String", "Character",
        "Array", "Dictionary", "Set", "Optional", "Result", "Void", "Any",
        "AnyObject", "Self", "Data", "Date", "URL", "CGFloat", "NSObject",
        "int", "long", "short", "char", "float", "double", "bool", "boolean",
        "byte", "void", "unsigned", "signed", "size_t", "str", "list", "dict",
        "tuple", "bytes", "object", "number", "Object", "Number", "Boolean",
        "Map", "List", "Vector", "i8", "i16", "i32", "i64", "u8", "u16",
        "u32", "u64", "f32", "f64", "usize", "isize",
    ]
}
