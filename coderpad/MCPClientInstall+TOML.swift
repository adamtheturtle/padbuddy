//
//  MCPClientInstall+TOML.swift
//  coderpad
//
//  The pure TOML side of the Codex one-click installer (#812/#813/#815): escaping the
//  executable path as a TOML basic string, recognizing every declaration form of
//  mcp_servers.padbuddy so a duplicate table is never appended, and rewriting only the
//  plain table form. Split from MCPClientInstall.swift to keep that file within lint
//  limits; internal (not private) so the unit tests can exercise it.
//

import Foundation

#if os(macOS)

    /// Tracks whether successive physical lines sit inside a multi-line TOML construct —
    /// a `"""`/`'''` string or an array value whose brackets haven't closed yet — so the
    /// line-based detector and rewriter never mistake a continuation line that happens to
    /// start with `[` for a table header (#1037). Internal for tests.
    struct TOMLLineState {
        private enum StringState { case notInString, multilineBasic, multilineLiteral }
        private var stringState = StringState.notInString
        private var bracketDepth = 0

        /// Whether the next physical line begins inside a multi-line construct.
        var isInsideMultilineConstruct: Bool { stringState != .notInString || bracketDepth > 0 }

        /// Consumes one physical line, updating the string/bracket state. Table headers
        /// self-balance their brackets, so only an unfinished array value leaves depth > 0.
        mutating func consume(_ line: String) {
            let characters = Array(line)
            var index = 0
            while index < characters.count {
                let next: Int? = switch stringState {
                case .multilineBasic: consumeInMultilineBasic(characters, at: index)
                case .multilineLiteral: consumeInMultilineLiteral(characters, at: index)
                case .notInString: consumeOutsideString(characters, at: index)
                }
                guard let next else { return } // comment ran to the end of the line

                index = next
            }
        }

        private mutating func consumeInMultilineBasic(_ characters: [Character], at index: Int) -> Int? {
            if characters[index] == "\\" { return index + 2 }
            if matches(characters, at: index, "\"\"\"") {
                stringState = .notInString
                return index + 3
            }
            return index + 1
        }

        private mutating func consumeInMultilineLiteral(_ characters: [Character], at index: Int) -> Int? {
            if matches(characters, at: index, "'''") {
                stringState = .notInString
                return index + 3
            }
            return index + 1
        }

        private mutating func consumeOutsideString(_ characters: [Character], at index: Int) -> Int? {
            switch characters[index] {
            case "#": return nil // comment runs to the end of the line
            case "\"" where matches(characters, at: index, "\"\"\""):
                stringState = .multilineBasic
                return index + 3
            case "'" where matches(characters, at: index, "'''"):
                stringState = .multilineLiteral
                return index + 3
            case "\"": return indexAfterBasicString(characters, from: index + 1)
            case "'": return indexAfterLiteralString(characters, from: index + 1)
            case "[": bracketDepth += 1; return index + 1
            case "]": bracketDepth = max(0, bracketDepth - 1); return index + 1
            default: return index + 1
            }
        }

        private func matches(_ characters: [Character], at index: Int, _ token: String) -> Bool {
            let tokenCharacters = Array(token)
            guard index + tokenCharacters.count <= characters.count else { return false }

            return Array(characters[index ..< index + tokenCharacters.count]) == tokenCharacters
        }

        /// The index just past a single-line basic string opened before `from`, honoring
        /// backslash escapes; an unterminated string (invalid TOML) runs to the line's end.
        private func indexAfterBasicString(_ characters: [Character], from: Int) -> Int {
            var index = from
            while index < characters.count {
                if characters[index] == "\\" { index += 2; continue }
                if characters[index] == "\"" { return index + 1 }
                index += 1
            }
            return index
        }

        private func indexAfterLiteralString(_ characters: [Character], from: Int) -> Int {
            var index = from
            while index < characters.count {
                if characters[index] == "'" { return index + 1 }
                index += 1
            }
            return index
        }
    }

    extension MCPClientInstall {
        /// Thrown when the existing config declares `mcp_servers.padbuddy` in a form the
        /// line-based rewriter can't safely replace (dotted key, inline table, array of tables).
        struct CodexConfigError: LocalizedError {
            let errorDescription: String?
        }

        /// How `mcp_servers.padbuddy` is already declared in a Codex config, if at all.
        enum CodexDeclaration {
            /// Not declared anywhere.
            case notDeclared
            /// Declared as a standard `[mcp_servers.padbuddy]` table header we can rewrite.
            case table
            /// Declared some other valid way (quoted keys aside, e.g. a dotted key or an inline
            /// table under `[mcp_servers]`) that line surgery can't safely replace.
            case other
        }

        /// Scans TOML text for any declaration that resolves to the `mcp_servers.padbuddy` key
        /// path: table headers (with optional whitespace or quoted keys), top-level dotted keys,
        /// and keys inside a `[mcp_servers]` table. Lines inside a multi-line array or string
        /// are continuations of a value, never declarations (#1037). Internal for tests.
        static func codexPadbuddyDeclaration(in text: String) -> CodexDeclaration {
            var currentTable: [String] = []
            var found = CodexDeclaration.notDeclared
            var state = TOMLLineState()
            for rawLine in text.components(separatedBy: "\n") {
                let wasContinuation = state.isInsideMultilineConstruct
                state.consume(rawLine)
                if wasContinuation { continue }

                let line = rawLine.trimmingCharacters(in: .whitespaces)
                if line.isEmpty || line.hasPrefix("#") { continue }

                if line.hasPrefix("[") {
                    let isArrayOfTables = line.hasPrefix("[[")
                    guard let path = tomlHeaderKeyPath(line) else { continue }

                    currentTable = path
                    if path == ["mcp_servers", "padbuddy"] {
                        // An array of tables ([[...]]) is a different shape; rewriting one
                        // header of it would corrupt the array, so it isn't safely replaceable.
                        return isArrayOfTables ? .other : .table
                    }
                    if path.count > 2, Array(path.prefix(2)) == ["mcp_servers", "padbuddy"] {
                        // A subtable like [mcp_servers.padbuddy.env] implicitly declares the
                        // padbuddy table; replacing just it would leave the rest behind.
                        found = .other
                    }
                    continue
                }

                guard let keyPath = tomlKeyValueKeyPath(line) else { continue }

                let fullPath = currentTable + keyPath
                if fullPath.count >= 2, Array(fullPath.prefix(2)) == ["mcp_servers", "padbuddy"] {
                    found = .other
                }
            }
            return found
        }

        /// The key path inside a `[table]` or `[[array-of-tables]]` header line, with quotes
        /// stripped from each component, or nil when the line isn't a well-formed header.
        private static func tomlHeaderKeyPath(_ line: String) -> [String]? {
            var inner = line
            while inner.hasPrefix("[") { inner.removeFirst() }
            guard let closing = inner.firstIndex(of: "]") else { return nil }

            inner = String(inner[..<closing])
            return inner.components(separatedBy: ".").map(normalizedTOMLKey)
        }

        /// The (possibly dotted) key path on the left of a `key = value` line, with quotes
        /// stripped, or nil for lines that aren't assignments.
        private static func tomlKeyValueKeyPath(_ line: String) -> [String]? {
            guard let equals = line.firstIndex(of: "=") else { return nil }

            let key = String(line[..<equals])
            guard !key.isEmpty else { return nil }

            return key.components(separatedBy: ".").map(normalizedTOMLKey)
        }

        /// A single TOML key component with surrounding whitespace and basic/literal quotes removed.
        private static func normalizedTOMLKey(_ component: String) -> String {
            var key = component.trimmingCharacters(in: .whitespaces)
            for quote in ["\"", "'"] where key.hasPrefix(quote) && key.hasSuffix(quote) && key.count >= 2 {
                key = String(key.dropFirst().dropLast())
            }
            return key
        }

        /// The `[mcp_servers.padbuddy]` TOML table, with a trailing blank line so it stays separated
        /// from anything that follows. Internal for tests.
        static func codexServerBlock(executablePath: String) -> String {
            """
            [mcp_servers.padbuddy]
            command = \(tomlBasicString(executablePath))
            args = ["--mcp"]

            """
        }

        /// Encodes `value` as a TOML basic string: quotes, backslashes, and control characters
        /// are escaped so any legal filesystem path round-trips as a single string value.
        /// Internal for tests.
        static func tomlBasicString(_ value: String) -> String {
            var escaped = ""
            for scalar in value.unicodeScalars {
                switch scalar {
                case "\\": escaped += "\\\\"
                case "\"": escaped += "\\\""
                case "\u{08}": escaped += "\\b"
                case "\t": escaped += "\\t"
                case "\n": escaped += "\\n"
                case "\u{0C}": escaped += "\\f"
                case "\r": escaped += "\\r"
                default:
                    if scalar.value < 0x20 || scalar.value == 0x7F {
                        escaped += String(format: "\\u%04X", scalar.value)
                    } else {
                        escaped.unicodeScalars.append(scalar)
                    }
                }
            }
            return "\"\(escaped)\""
        }

        /// Replaces the existing `[mcp_servers.padbuddy]` table (its header through the line before
        /// the next table header, or the end of file) with `block`, leaving every other table
        /// untouched. The next-header search is multi-line aware: a `[` that merely continues a
        /// multi-line array or string is part of the table body, not a new table (#1037).
        /// Internal for tests.
        static func replacingCodexServer(in text: String, with block: String) -> String {
            let lines = text.components(separatedBy: "\n")
            var result: [String] = []
            var state = TOMLLineState()
            var index = 0
            while index < lines.count {
                let wasContinuation = state.isInsideMultilineConstruct
                if !wasContinuation,
                   tomlHeaderKeyPath(lines[index].trimmingCharacters(in: .whitespaces))
                   == ["mcp_servers", "padbuddy"],
                   !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("[[") {
                    result.append(contentsOf: block.components(separatedBy: "\n"))
                    state.consume(lines[index])
                    index += 1
                    while index < lines.count {
                        if !state.isInsideMultilineConstruct,
                           lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("[") { break }

                        state.consume(lines[index])
                        index += 1
                    }
                } else {
                    state.consume(lines[index])
                    result.append(lines[index])
                    index += 1
                }
            }
            return result.joined(separator: "\n")
        }
    }

#endif
