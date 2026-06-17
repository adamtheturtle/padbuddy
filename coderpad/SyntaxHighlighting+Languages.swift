//
//  SyntaxHighlighting+Languages.swift
//  coderpad
//

import Foundation

/// Per-language lexing rules. Languages are grouped into families that share
/// comment, string, and keyword conventions.
struct LanguageSyntax {
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

    static func forLanguage(_ language: String?) -> Self {
        let lang = (language ?? "").lowercased()
        // C-family rules apply to anything not explicitly listed.
        var syntax = byLanguage[lang] ?? cFamily
        // Ensure longer delimiters are matched before their prefixes.
        syntax.stringDelimiters.sort { $0.count > $1.count }
        return syntax
    }

    /// Convenience for building a delimiter list from strings.
    private static func delimiters(_ values: String...) -> [[Character]] {
        values.map { Array($0) }
    }

    /// Rules for the C-family and any unrecognised language.
    private static let cFamily = Self(
        keywords: Keywords.cLike, types: Types.common,
        lineComments: [Array("//")], blockComments: [.init("/*", "*/")],
        stringDelimiters: delimiters("\"", "'", "`")
    )

    /// Explicit rules per language code; codes absent here use ``cFamily``.
    private static let byLanguage: [String: Self] = {
        let python = Self(
            keywords: Keywords.python, types: Types.common,
            lineComments: [Array("#")], blockComments: [],
            stringDelimiters: delimiters("\"\"\"", "'''", "\"", "'")
        )
        let ruby = Self(
            keywords: Keywords.ruby, types: Types.common,
            lineComments: [Array("#")], blockComments: [],
            stringDelimiters: delimiters("\"", "'")
        )
        let shell = Self(
            keywords: Keywords.shell, types: [],
            lineComments: [Array("#")], blockComments: [],
            stringDelimiters: delimiters("\"", "'")
        )
        let sql = Self(
            keywords: Keywords.sql, types: [],
            lineComments: [Array("--")], blockComments: [.init("/*", "*/")],
            stringDelimiters: delimiters("'", "\""),
            escapesWithBackslash: false, caseInsensitiveKeywords: true
        )
        let lua = Self(
            keywords: Keywords.lua, types: [],
            lineComments: [Array("--")], blockComments: [.init("--[[", "]]")],
            stringDelimiters: delimiters("\"", "'")
        )
        let haskell = Self(
            keywords: Keywords.haskell, types: Types.common,
            lineComments: [Array("--")], blockComments: [.init("{-", "-}")],
            stringDelimiters: delimiters("\"")
        )
        let clojure = Self(
            keywords: Keywords.lisp, types: [],
            lineComments: [Array(";")], blockComments: [],
            stringDelimiters: delimiters("\"")
        )
        let erlang = Self(
            keywords: Keywords.cLike, types: [],
            lineComments: [Array("%")], blockComments: [],
            stringDelimiters: delimiters("\"")
        )
        let ocaml = Self(
            keywords: Keywords.cLike, types: Types.common,
            lineComments: [], blockComments: [.init("(*", "*)")],
            stringDelimiters: delimiters("\"")
        )
        let fsharp = Self(
            keywords: Keywords.cLike, types: Types.common,
            lineComments: [Array("//")], blockComments: [.init("(*", "*)")],
            stringDelimiters: delimiters("\"")
        )
        let html = Self(
            keywords: [], types: [],
            lineComments: [], blockComments: [.init("<!--", "-->")],
            stringDelimiters: delimiters("\"", "'")
        )
        let css = Self(
            keywords: [], types: [],
            lineComments: [], blockComments: [.init("/*", "*/")],
            stringDelimiters: delimiters("\"", "'")
        )
        let swift = Self(
            keywords: Keywords.cLike, types: Types.common,
            lineComments: [Array("//")], blockComments: [.init("/*", "*/")],
            stringDelimiters: delimiters("\"\"\"", "\"", "'")
        )
        return [
            "python": python, "python2": python, "python3": python,
            "ruby": ruby,
            "bash": shell, "shell": shell, "sh": shell,
            "sql": sql, "mysql": sql, "postgresql": sql, "postgres": sql,
            "lua": lua,
            "haskell": haskell,
            "clojure": clojure,
            "erlang": erlang,
            "ocaml": ocaml, "fsharp": fsharp, "f#": fsharp,
            "html": html,
            "css": css,
            "swift": swift
        ]
    }()
}

enum Keywords {
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
        "with", "lambda", "repeat", "fallthrough", "begin", "end", "then"
    ]

    static let python: Set<String> = [
        "def", "class", "return", "if", "elif", "else", "for", "while",
        "break", "continue", "pass", "import", "from", "as", "with", "try",
        "except", "finally", "raise", "lambda", "yield", "global", "nonlocal",
        "del", "in", "is", "not", "and", "or", "async", "await", "assert",
        "None", "True", "False", "self", "cls", "match", "case"
    ]

    static let ruby: Set<String> = [
        "def", "end", "class", "module", "if", "elsif", "else", "unless",
        "while", "until", "for", "break", "next", "redo", "retry", "return",
        "yield", "do", "begin", "rescue", "ensure", "raise", "then", "case",
        "when", "in", "nil", "true", "false", "self", "super", "require",
        "require_relative", "attr_accessor", "attr_reader", "attr_writer",
        "lambda", "proc", "and", "or", "not", "defined?"
    ]

    static let shell: Set<String> = [
        "if", "then", "else", "elif", "fi", "for", "while", "do", "done",
        "case", "esac", "function", "in", "select", "until", "return",
        "local", "export", "readonly", "declare", "set", "unset", "source",
        "alias", "echo", "exit", "break", "continue"
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
        "unique", "check", "asc", "desc", "true", "false"
    ]

    static let lua: Set<String> = [
        "and", "break", "do", "else", "elseif", "end", "false", "for",
        "function", "goto", "if", "in", "local", "nil", "not", "or", "repeat",
        "return", "then", "true", "until", "while"
    ]

    static let haskell: Set<String> = [
        "module", "where", "import", "data", "type", "newtype", "class",
        "instance", "deriving", "do", "let", "in", "if", "then", "else",
        "case", "of", "return", "qualified", "as", "hiding"
    ]

    static let lisp: Set<String> = [
        "def", "defn", "defmacro", "defmulti", "defmethod", "let", "fn",
        "if", "when", "cond", "do", "loop", "recur", "ns", "require",
        "import", "true", "false", "nil", "and", "or", "not", "for", "doseq"
    ]
}

enum Types {
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
        "u32", "u64", "f32", "f64", "usize", "isize"
    ]
}
