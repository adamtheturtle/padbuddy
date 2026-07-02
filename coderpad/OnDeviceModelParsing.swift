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
        for label in labels {
            if let range = reply.range(of: label + ":", options: .caseInsensitive) {
                positions.append((label, range))
            }
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

    /// Parses `key: value` lines into a map keyed by a normalized (lowercased, spaces and
    /// hyphens removed) key, so `dateRange`, `date range`, and `date-range` all land under
    /// `daterange`. Blank values and the model's ways of saying "not set" (`nil`, `none`,
    /// `n/a`, `null`, `-`) are dropped, and surrounding quotes are stripped. Suits the flat
    /// filter replies where each field is a single line.
    static func keyedFields(_ reply: String) -> [String: String] {
        var result: [String: String] = [:]
        for rawLine in reply.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            guard let colon = line.firstIndex(of: ":") else { continue }

            let key = line[..<colon]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "-", with: "")
            guard !key.isEmpty else { continue }

            var value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            let lowered = value.lowercased()
            guard !value.isEmpty, !["nil", "none", "n/a", "null", "-"].contains(lowered) else { continue }
            result[key] = value
        }
        return result
    }
}
