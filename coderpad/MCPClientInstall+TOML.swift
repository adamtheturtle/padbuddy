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
        /// and keys inside a `[mcp_servers]` table. Internal for tests.
        static func codexPadbuddyDeclaration(in text: String) -> CodexDeclaration {
            var currentTable: [String] = []
            var found = CodexDeclaration.notDeclared
            for rawLine in text.components(separatedBy: "\n") {
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
        /// untouched. Internal for tests.
        static func replacingCodexServer(in text: String, with block: String) -> String {
            let lines = text.components(separatedBy: "\n")
            var result: [String] = []
            var index = 0
            while index < lines.count {
                if tomlHeaderKeyPath(lines[index].trimmingCharacters(in: .whitespaces))
                    == ["mcp_servers", "padbuddy"],
                    !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("[[") {
                    result.append(contentsOf: block.components(separatedBy: "\n"))
                    index += 1
                    while index < lines.count,
                          !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("[") {
                        index += 1
                    }
                } else {
                    result.append(lines[index])
                    index += 1
                }
            }
            return result.joined(separator: "\n")
        }
    }

#endif
