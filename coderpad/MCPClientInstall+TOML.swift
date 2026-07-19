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
    /// start with `[` for a table header (#1037). Internal for tests; nonisolated so the
    /// installer can scan configs off the main actor (#2270).
    nonisolated struct TOMLLineState {
        private enum StringState { case notInString, multilineBasic, multilineLiteral }
        private var stringState = StringState.notInString
        private var bracketDepth = 0

        /// Whether the next physical line begins inside a multi-line construct.
        var isInsideMultilineConstruct: Bool {
            stringState != .notInString || bracketDepth > 0
        }

        /// Consumes one physical line, updating the string/bracket state. Walks the line's own
        /// indices so no per-line character array is materialized (#2261). Table headers
        /// self-balance their brackets, so only an unfinished array value leaves depth > 0.
        mutating func consume(_ line: String) {
            var index = line.startIndex
            while index < line.endIndex {
                let next: String.Index? = switch stringState {
                case .multilineBasic: consumeInMultilineBasic(line, at: index)
                case .multilineLiteral: consumeInMultilineLiteral(line, at: index)
                case .notInString: consumeOutsideString(line, at: index)
                }
                guard let next else { return }

                // comment ran to the end of the line

                index = next
            }
        }

        private mutating func consumeInMultilineBasic(_ line: String, at index: String.Index) -> String.Index? {
            if line[index] == "\\" {
                return line.index(index, offsetBy: 2, limitedBy: line.endIndex) ?? line.endIndex
            }
            if line[index...].hasPrefix("\"\"\"") {
                stringState = .notInString
                return line.index(index, offsetBy: 3)
            }
            return line.index(after: index)
        }

        private mutating func consumeInMultilineLiteral(_ line: String, at index: String.Index) -> String.Index? {
            if line[index...].hasPrefix("'''") {
                stringState = .notInString
                return line.index(index, offsetBy: 3)
            }
            return line.index(after: index)
        }

        private mutating func consumeOutsideString(_ line: String, at index: String.Index) -> String.Index? {
            switch line[index] {
            case "#": return nil // comment runs to the end of the line
            case "\"" where line[index...].hasPrefix("\"\"\""):
                stringState = .multilineBasic
                return line.index(index, offsetBy: 3)

            case "'" where line[index...].hasPrefix("'''"):
                stringState = .multilineLiteral
                return line.index(index, offsetBy: 3)

            case "\"": return indexAfterBasicString(line, from: line.index(after: index))

            case "'": return indexAfterLiteralString(line, from: line.index(after: index))

            case "[": bracketDepth += 1; return line.index(after: index)

            case "]": bracketDepth = max(0, bracketDepth - 1); return line.index(after: index)

            default: return line.index(after: index)
            }
        }

        /// The index just past a single-line basic string opened before `from`, honoring
        /// backslash escapes; an unterminated string (invalid TOML) runs to the line's end.
        private func indexAfterBasicString(_ line: String, from: String.Index) -> String.Index {
            var index = from
            while index < line.endIndex {
                if line[index] == "\\" {
                    index = line.index(index, offsetBy: 2, limitedBy: line.endIndex) ?? line.endIndex
                    continue
                }
                if line[index] == "\"" { return line.index(after: index) }

                index = line.index(after: index)
            }
            return index
        }

        private func indexAfterLiteralString(_ line: String, from: String.Index) -> String.Index {
            var index = from
            while index < line.endIndex {
                if line[index] == "'" { return line.index(after: index) }

                index = line.index(after: index)
            }
            return index
        }
    }

    // Nonisolated: pure text processing, run off the main actor by the installer (#2270).
    nonisolated extension MCPClientInstall {
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

        /// One shared walk over a Codex config: the declaration verdict plus, for the plain
        /// table form, the line range the rewriter should replace. Letting the installer scan
        /// once instead of running separate detect and rewrite passes (#2264).
        struct CodexConfigScan {
            let declaration: CodexDeclaration
            /// The config split into physical lines, shared with the caller so it isn't split again.
            let lines: [String]
            /// For `.table`: the header line through the line before the next table header
            /// (or the end of file) — the whole replaceable table.
            let tableLineRange: Range<Int>?
        }

        /// Scans TOML text for any declaration that resolves to the `mcp_servers.padbuddy` key
        /// path: table headers (with optional whitespace or quoted keys), top-level dotted keys,
        /// and keys inside a `[mcp_servers]` table. Lines inside a multi-line array or string
        /// are continuations of a value, never declarations (#1037). Internal for tests.
        static func codexPadbuddyDeclaration(in text: String) -> CodexDeclaration {
            scanCodexConfig(text).declaration
        }

        /// The single detect pass behind `codexPadbuddyDeclaration` and the installer's rewrite,
        /// so the file is split and state-walked exactly once per install (#2264).
        static func scanCodexConfig(_ text: String) -> CodexConfigScan {
            let lines = text.components(separatedBy: "\n")
            var currentTable: [String] = []
            var found = CodexDeclaration.notDeclared
            var state = TOMLLineState()
            var index = 0
            while index < lines.count {
                let rawLine = lines[index]
                let wasContinuation = state.isInsideMultilineConstruct
                state.consume(rawLine)
                defer { index += 1 }
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
                        if isArrayOfTables {
                            return CodexConfigScan(declaration: .other, lines: lines, tableLineRange: nil)
                        }

                        return CodexConfigScan(
                            declaration: .table,
                            lines: lines,
                            tableLineRange: tableBody(startingAt: index, in: lines, state: &state)
                        )
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
            return CodexConfigScan(declaration: found, lines: lines, tableLineRange: nil)
        }

        /// The line range of the table whose header sits at `headerIndex`: the header through
        /// the line before the next table header (multi-line aware), or the end of file.
        private static func tableBody(
            startingAt headerIndex: Int,
            in lines: [String],
            state: inout TOMLLineState
        ) -> Range<Int> {
            var index = headerIndex + 1
            while index < lines.count {
                if !state.isInsideMultilineConstruct,
                   lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("[") { break }

                state.consume(lines[index])
                index += 1
            }
            return headerIndex ..< index
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
        /// Unescaped runs are appended as whole slices rather than scalar by scalar (#2272).
        /// Internal for tests.
        static func tomlBasicString(_ value: String) -> String {
            let scalars = value.unicodeScalars
            var escaped = ""
            escaped.reserveCapacity(value.utf8.count + 2)
            escaped.append("\"")
            var runStart = scalars.startIndex
            var index = scalars.startIndex
            while index < scalars.endIndex {
                let scalar = scalars[index]
                let replacement: String? = switch scalar {
                case "\\": "\\\\"
                case "\"": "\\\""
                case "\u{08}": "\\b"
                case "\t": "\\t"
                case "\n": "\\n"
                case "\u{0C}": "\\f"
                case "\r": "\\r"
                default:
                    scalar.value < 0x20 || scalar.value == 0x7F
                        ? String(format: "\\u%04X", scalar.value)
                        : nil
                }
                let next = scalars.index(after: index)
                if let replacement {
                    escaped.unicodeScalars.append(contentsOf: scalars[runStart ..< index])
                    escaped += replacement
                    runStart = next
                }
                index = next
            }
            escaped.unicodeScalars.append(contentsOf: scalars[runStart...])
            escaped.append("\"")
            return escaped
        }

        /// Replaces the existing `[mcp_servers.padbuddy]` table (its header through the line before
        /// the next table header, or the end of file) with `block`, leaving every other table
        /// untouched. The next-header search is multi-line aware: a `[` that merely continues a
        /// multi-line array or string is part of the table body, not a new table (#1037).
        /// Each line is trimmed once, not once per check (#2265). Internal for tests.
        static func replacingCodexServer(in text: String, with block: String) -> String {
            let lines = text.components(separatedBy: "\n")
            let blockLines = block.components(separatedBy: "\n")
            var result: [String] = []
            result.reserveCapacity(lines.count + blockLines.count)
            var state = TOMLLineState()
            var index = 0
            while index < lines.count {
                let wasContinuation = state.isInsideMultilineConstruct
                let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
                if !wasContinuation,
                   !trimmed.hasPrefix("[["),
                   tomlHeaderKeyPath(trimmed) == ["mcp_servers", "padbuddy"] {
                    result.append(contentsOf: blockLines)
                    state.consume(lines[index])
                    index = tableBody(startingAt: index, in: lines, state: &state).upperBound
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
