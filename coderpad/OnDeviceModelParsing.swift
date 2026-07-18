import Foundation

/// Parsing helpers for the on-device model's *plain-text* replies.
///
/// The app talks to FoundationModels over `LanguageModelSession.respond(to:)` and never
/// `@Generable` / `respond(to:generating:)`: the accessor that macro emits
/// (`Generable.promptRepresentation`) is absent on some shipping OS builds and aborts the
/// process at dyld load. So each on-device feature asks the model for a simple labeled
/// text format and reconstructs its fields here instead. These functions are pure and
/// off-main-safe, so they're unit-testable without the model.
enum OnDeviceModelParsing {
    /// Splits a reply made of `Label: value` sections into a `label -> value` map. Each
    /// label is located case-insensitively, and its section runs until the next label that
    /// is actually present (in reply order) or the end of the reply - so a value may span
    /// multiple lines, which a code block or a multi-sentence field needs. Labels the model
    /// omitted are simply absent from the result.
    static func labeledSections(_ reply: String, labels: [String]) -> [String: String] {
        var positions: [(label: String, range: Range<String.Index>)] = []
        // Labels must appear in the requested order: the model is instructed to
        // reply with the sections in exactly that order, and matching any label
        // anywhere let source code echoed inside one section (a line starting
        // "SUMMARY:") hijack a later section's start (#1716).
        var nextLabelIndex = 0
        var lineStart = reply.startIndex
        while lineStart < reply.endIndex, nextLabelIndex < labels.count {
            var lineEnd = lineStart
            while lineEnd < reply.endIndex, !reply[lineEnd].isNewline {
                lineEnd = reply.index(after: lineEnd)
            }

            var labelStart = lineStart
            while labelStart < lineEnd, reply[labelStart].isWhitespace {
                labelStart = reply.index(after: labelStart)
            }

            let line = reply[labelStart ..< lineEnd]
            for offset in nextLabelIndex ..< labels.count {
                let label = labels[offset]
                if let range = line.range(of: label + ":", options: [.anchored, .caseInsensitive]) {
                    positions.append((label, range))
                    nextLabelIndex = offset + 1
                    break
                }
            }

            if lineEnd == reply.endIndex {
                break
            }
            lineStart = reply.index(after: lineEnd)
        }
        positions.sort { $0.range.lowerBound < $1.range.lowerBound }

        var result: [String: String] = [:]
        for (index, entry) in positions.enumerated() {
            let start = entry.range.upperBound
            let end = index + 1 < positions.count ? positions[index + 1].range.lowerBound : reply.endIndex
            result[entry.label] = String(reply[start ..< end]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    /// Parses `key: value` lines into a map keyed by a normalized (lowercased; spaces,
    /// hyphens, and underscores removed) key, so `dateRange`, `date range`, `date-range`,
    /// and `date_range` all land under `daterange` (#1714). Blank values and the model's
    /// ways of saying "not set" (`nil`, `none`, `n/a`, `null`, `-`) are dropped, and
    /// surrounding quotes are stripped. A key the model repeats with *conflicting*
    /// values is dropped entirely rather than trusting whichever occurrence came last
    /// (#1715); repeating the same value is harmless and kept. Suits the flat filter
    /// replies where each field is a single line.
    static func keyedFields(_ reply: String) -> [String: String] {
        var result: [String: String] = [:]
        var conflicted = Set<String>()
        for rawLine in reply.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            guard let colon = line.firstIndex(of: ":") else { continue }

            let key = line[..<colon]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "-", with: "")
                .replacingOccurrences(of: "_", with: "")
            guard !key.isEmpty else { continue }

            var value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            let lowered = value.lowercased()
            guard !value.isEmpty, !["nil", "none", "n/a", "null", "-"].contains(lowered) else { continue }

            if let existing = result[key], existing != value {
                conflicted.insert(key)
                continue
            }
            result[key] = value
        }
        for key in conflicted {
            result.removeValue(forKey: key)
        }
        return result
    }
}
