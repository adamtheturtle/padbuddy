//
//  MCPClientInstall+TOMLKeys.swift
//  coderpad
//
//  TOML key-path parsing for the Codex installer: splitting dotted paths without
//  breaking quoted components, interpreting basic-string escapes, and rejecting
//  malformed table headers. Split from MCPClientInstall+TOML.swift for file
//  length; internal (not private) so the unit tests can exercise it.
//

import Foundation

#if os(macOS)

    nonisolated extension MCPClientInstall {
        /// The key path inside a `[table]` or `[[array-of-tables]]` header line, or nil
        /// when the line isn't a well-formed header.
        ///
        /// Everything after the closing bracket must be blank or a comment. Taking the
        /// text through the first `]` and ignoring the rest meant a corrupt line like
        /// `[mcp_servers.padbuddy] garbage` was accepted as a real table and became a
        /// rewrite target — editing a region of a file that TOML itself rejects
        /// (#2542).
        static func tomlHeaderKeyPath(_ line: String) -> [String]? {
            var inner = line
            var openers = 0
            while inner.hasPrefix("[") {
                inner.removeFirst()
                openers += 1
            }
            guard openers == 1 || openers == 2 else { return nil }
            guard let closing = inner.firstIndex(of: "]") else { return nil }

            let key = String(inner[..<closing])
            var trailing = String(inner[inner.index(after: closing)...])
            // An array-of-tables header closes with a second bracket.
            if openers == 2 {
                guard trailing.hasPrefix("]") else { return nil }

                trailing.removeFirst()
            }
            let rest = trailing.trimmingCharacters(in: .whitespaces)
            guard rest.isEmpty || rest.hasPrefix("#") else { return nil }

            return splitTOMLKeyPath(key)
        }

        /// The (possibly dotted) key path on the left of a `key = value` line, or nil
        /// for lines that aren't assignments.
        static func tomlKeyValueKeyPath(_ line: String) -> [String]? {
            // Find the `=` that sits outside any quoted key component: a quoted key may
            // legally contain one.
            guard let equals = indexOfUnquoted("=", in: line) else { return nil }

            let key = String(line[..<equals])
            guard !key.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }

            return splitTOMLKeyPath(key)
        }

        /// Splits a dotted TOML key path, honouring quoting, or nil when the quoting is
        /// unbalanced.
        ///
        /// Splitting on every `.` broke any legal quoted key containing one —
        /// `"my.server" = { … }` read as the two-segment path `my` / `server`, which
        /// both invented PadBuddy declarations that weren't there and hid real ones
        /// (#2537).
        static func splitTOMLKeyPath(_ key: String) -> [String]? {
            var components: [String] = []
            var current = ""
            var quote: Character?
            var index = key.startIndex
            while index < key.endIndex {
                let character = key[index]
                if let open = quote {
                    if character == "\\", open == "\"" {
                        // Escapes only exist in basic strings; keep both characters so
                        // unescaping can interpret them.
                        current.append(character)
                        index = key.index(after: index)
                        if index < key.endIndex {
                            current.append(key[index])
                            index = key.index(after: index)
                        }
                        continue
                    }
                    if character == open { quote = nil } else { current.append(character) }
                } else if character == "\"" || character == "'" {
                    quote = character
                } else if character == "." {
                    components.append(current)
                    current = ""
                } else {
                    current.append(character)
                }
                index = key.index(after: index)
            }
            guard quote == nil else { return nil }

            components.append(current)
            return components.map { unescapedTOMLKey($0.trimmingCharacters(in: .whitespaces)) }
        }

        /// The first occurrence of `character` that is not inside a quoted key.
        private static func indexOfUnquoted(_ character: Character, in line: String) -> String.Index? {
            var quote: Character?
            var index = line.startIndex
            while index < line.endIndex {
                let current = line[index]
                if let open = quote {
                    if current == "\\", open == "\"" {
                        index = line.index(index, offsetBy: 2, limitedBy: line.endIndex) ?? line.endIndex
                        continue
                    }
                    if current == open { quote = nil }
                } else if current == "\"" || current == "'" {
                    quote = current
                } else if current == character {
                    return index
                }
                index = line.index(after: index)
            }
            return nil
        }

        /// Interprets the escape sequences a TOML basic-string key may contain.
        ///
        /// Only the outer quotes were stripped before, so `"a\\"b"` and `"a\\\\b"` compared
        /// as their raw source text rather than their real values — enough for a key to
        /// be mistaken for a PadBuddy path, or to slip past collision detection (#2544).
        /// Literal (single-quoted) keys have no escapes by definition and pass through.
        static func unescapedTOMLKey(_ component: String) -> String {
            guard component.contains("\\") else { return component }

            var result = ""
            var index = component.startIndex
            while index < component.endIndex {
                guard component[index] == "\\",
                      let next = component.index(index, offsetBy: 1, limitedBy: component.endIndex),
                      next < component.endIndex
                else {
                    result.append(component[index])
                    index = component.index(after: index)
                    continue
                }

                switch component[next] {
                case "n": result.append("\n")
                case "t": result.append("\t")
                case "r": result.append("\r")
                case "\"": result.append("\"")
                case "\\": result.append("\\")
                default:
                    // Not an escape TOML defines; keep it verbatim rather than guessing.
                    result.append(component[index])
                    result.append(component[next])
                }
                index = component.index(after: next)
            }
            return result
        }
    }

#endif
