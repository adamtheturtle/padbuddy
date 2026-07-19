//
//  MCPClientInstall+TOMLRewrite.swift
//  coderpad
//
//  Building the replacement text for Codex's config.toml: matching the file's
//  line-ending convention and keeping the settings in the PadBuddy table that
//  PadBuddy doesn't own. Split from MCPClientInstall+TOML.swift for file length;
//  internal (not private) so the unit tests can exercise it.
//

import Foundation

#if os(macOS)

    nonisolated extension MCPClientInstall {
        /// The line ending `text` uses, so a rewrite doesn't convert the file.
        ///
        /// The rewriter splits on "\n" and joins with "\n". On a CRLF config the
        /// untouched lines keep their trailing "\r" but freshly written ones didn't,
        /// leaving a mixed file — a routine server update producing an unrelated
        /// whole-file diff, and breaking tooling that expects one convention (#2543).
        static func dominantLineEnding(of text: String) -> String {
            text.contains("\r\n") ? "\r\n" : "\n"
        }

        /// The replacement lines for an existing `[mcp_servers.padbuddy]` table:
        /// PadBuddy's own `command` and `args`, plus everything else that was already
        /// in the table.
        ///
        /// The whole body used to be discarded and rewritten as just those two keys, so
        /// merely updating the app's path silently deleted any `env`, `startup_timeout`,
        /// `enabled`, or custom header the user had added (#2536). Only the two keys
        /// PadBuddy owns are replaced; the rest is copied through in its original order,
        /// continuation lines of multi-line values included.
        static func codexTableReplacement(body: [String], executablePath: String) -> [String] {
            var preserved: [String] = []
            var state = TOMLLineState()
            var index = 1 // skip the header; the caller re-emits it
            while index < body.count {
                let wasContinuation = state.isInsideMultilineConstruct
                let line = body[index]
                state.consume(line)
                index += 1
                if wasContinuation {
                    // Belongs to a value we already decided about.
                    if !preserved.isEmpty { preserved.append(line) }
                    continue
                }

                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { continue }
                if let key = tomlKeyValueKeyPath(trimmed), key == ["command"] || key == ["args"] {
                    // Ours to define. Skip its continuation lines too.
                    while index < body.count, state.isInsideMultilineConstruct {
                        state.consume(body[index])
                        index += 1
                    }
                    continue
                }
                preserved.append(line)
            }
            return ["[mcp_servers.padbuddy]",
                    "command = \(tomlBasicString(executablePath))",
                    "args = [\"--mcp\"]"] + preserved
        }
    }

#endif
