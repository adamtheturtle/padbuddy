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
    static let maximumLabeledReplyBytes = 1_250_000
    static let maximumLabeledSectionBytes = 400_000
    static let maximumLabeledLines = 8192

    static func labeledSections(_ reply: String, labels: [String]) -> [String: String] {
        guard reply.utf8.prefix(maximumLabeledReplyBytes + 1).count <= maximumLabeledReplyBytes else { return [:] }

        return parseLabeledSections(reply, labels: labels)
    }

    private static func parseLabeledSections(_ reply: String, labels: [String]) -> [String: String] {
        var positions: [(label: String, range: Range<String.Index>)] = []
        // Labels must appear in the requested order: the model is instructed to
        // reply with the sections in exactly that order, and matching any label
        // anywhere let source code echoed inside one section (a line starting
        // "SUMMARY:") hijack a later section's start (#1716).
        var nextLabelIndex = 0
        // Lines inside a ``` fence are quoted source, never section headers: a
        // code block containing "SUMMARY:" must stay content even when the real
        // section header hasn't appeared yet (#1962).
        var inFence = false
        var lineStart = reply.startIndex
        var lineCount = 0
        while lineStart < reply.endIndex {
            lineCount += 1
            guard lineCount <= maximumLabeledLines else { return [:] }

            var lineEnd = lineStart
            while lineEnd < reply.endIndex, !reply[lineEnd].isNewline {
                lineEnd = reply.index(after: lineEnd)
            }

            var labelStart = lineStart
            while labelStart < lineEnd, reply[labelStart].isWhitespace {
                labelStart = reply.index(after: labelStart)
            }

            let line = reply[labelStart ..< lineEnd]
            if line.hasPrefix("```") {
                inFence.toggle()
            } else if !inFence {
                if !positions.isEmpty,
                   let range = labeledHeaderRange(in: line, label: labels[nextLabelIndex - 1]) {
                    // The model corrected itself by re-emitting the current
                    // section's header: the later occurrence wins over the stale
                    // first answer (#1963). Only the *current* label re-matches;
                    // an earlier label repeated later stays content (#1716).
                    positions[positions.count - 1] = (labels[nextLabelIndex - 1], range)
                } else {
                    for offset in nextLabelIndex ..< labels.count {
                        if let range = labeledHeaderRange(in: line, label: labels[offset]) {
                            positions.append((labels[offset], range))
                            nextLabelIndex = offset + 1
                            break
                        }
                    }
                }
            }

            if lineEnd == reply.endIndex {
                break
            }
            lineStart = reply.index(after: lineEnd)
        }

        return labeledValues(in: reply, positions: positions)
    }

    private static func labeledValues(
        in reply: String, positions: [(label: String, range: Range<String.Index>)]
    ) -> [String: String] {
        var result: [String: String] = [:]
        for (index, entry) in positions.enumerated() {
            let start = entry.range.upperBound
            let end = index + 1 < positions.count ? positions[index + 1].range.lowerBound : reply.endIndex
            let section = reply[start ..< end]
            guard section.utf8.prefix(maximumLabeledSectionBytes + 1).count <= maximumLabeledSectionBytes else {
                return [:]
            }

            result[entry.label] = String(section).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    /// Matches `Label:` and the common model variant `Label :`, without letting
    /// a longer word that merely starts with the label become a header (#2807).
    private static func labeledHeaderRange(in line: Substring, label: String) -> Range<String.Index>? {
        guard let labelRange = line.range(of: label, options: [.anchored, .caseInsensitive]) else { return nil }

        var colon = labelRange.upperBound
        while colon < line.endIndex, line[colon].isWhitespace {
            colon = line.index(after: colon)
        }
        guard colon < line.endIndex, line[colon] == ":" else { return nil }

        return labelRange.lowerBound ..< line.index(after: colon)
    }

    /// Parses `key: value` lines into a map keyed by a normalized (lowercased; spaces,
    /// hyphens, and underscores removed) key, so `dateRange`, `date range`, `date-range`,
    /// and `date_range` all land under `daterange` (#1714). Blank values and the model's
    /// ways of saying "not set" (`nil`, `none`, `n/a`, `null`, `-`) are dropped, and
    /// surrounding quotes are stripped. A key the model repeats with *conflicting*
    /// values is dropped entirely rather than trusting whichever occurrence came last
    /// (#1715); repeating the same value is harmless and kept. Suits the flat filter
    /// replies where each field is a single line.
    /// Caps on what a reply may contribute.
    ///
    /// The model's output is untrusted text: a malformed or looping reply could
    /// otherwise fill an unbounded dictionary with unbounded strings and pass it
    /// downstream as filter data (#2425). These are far above any real label or
    /// value the prompts ask for, so a well-formed reply never meets them.
    static let maxFieldCount = 64
    static let maxKeyLength = 64
    static let maxValueLength = 2048

    /// Work limits, independent of how many fields are *accepted*. The count above only
    /// advanced on a successful insert, so a reply made entirely of colonless, blank, or
    /// oversized lines was scanned and allocated in full however long it ran (#4567).
    static let maxReplyLength = 65536
    static let maxLineCount = 512

    static func keyedFields(_ reply: String) -> [String: String] {
        var result: [String: String] = [:]
        var conflicted = Set<String>()
        var linesRead = 0
        // Bounding the input as well as the output keeps a reply of rejected lines from
        // costing work in proportion to its length (#4567). `maxLineCount` in turn bounds
        // `conflicted`, which is not capped by `maxFieldCount`.
        for rawLine in reply.prefix(maxReplyLength).split(whereSeparator: \.isNewline) {
            linesRead += 1
            guard linesRead <= maxLineCount else { break }

            // Stop once enough fields have been collected; a reply with more than
            // this isn't the shape the prompt asked for.
            guard result.count < maxFieldCount else { break }

            let line = String(rawLine)
            guard let colon = line.firstIndex(of: ":") else { continue }

            // Normalize in one pass: lowercasing and dropping separators via chained
            // replacingOccurrences rescans and reallocates the key four times per
            // line (#2269). `isWhitespace` rather than a literal " ", so a label
            // written with a nonbreaking or other Unicode space normalizes to the
            // same key as its plain-space twin (#2427).
            let rawKey = line[..<colon].trimmingCharacters(in: .whitespacesAndNewlines)
            var key = ""
            key.reserveCapacity(rawKey.count)
            for character in rawKey where !character.isWhitespace && character != "-" && character != "_" {
                key.append(contentsOf: character.lowercased())
            }
            guard !key.isEmpty, key.count <= maxKeyLength else { continue }

            var value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if value.count >= 2, let quote = value.first,
               quote == "\"" || quote == "'", value.last == quote {
                value.removeFirst()
                value.removeLast()
            }
            let lowered = value.lowercased()
            guard !value.isEmpty, value.count <= maxValueLength,
                  !["nil", "none", "n/a", "null", "-"].contains(lowered) else { continue }

            // A conflicted key stays dropped, so a later repeat of one of its values
            // cannot resurrect it.
            guard !conflicted.contains(key) else { continue }

            if let existing = result[key], existing != value {
                // Removed here rather than after the loop: leaving the provisional entry
                // in place let 64 deliberately conflicting keys fill the field cap, so
                // every valid field after them was never read (#4566).
                result.removeValue(forKey: key)
                conflicted.insert(key)
                continue
            }
            result[key] = value
        }
        return result
    }
}
