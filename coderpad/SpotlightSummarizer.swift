import Foundation

/// Generates a handful of concise search keywords for a question from its text,
/// using Apple's on-device FoundationModels, so the Spotlight index surfaces it
/// for terms that don't appear verbatim in its title. Additive and private like
/// ``SavedSearchNamer``: on-device only, macOS 26+ with an available model, and
/// it rides on top of the existing **opt-in** Spotlight indexing — nothing new is
/// indexed that wasn't already, the keywords just enrich items the user chose to
/// index. See ``SpotlightIndexer``.
///
/// The on-device round-trip now lives in buddy-kit's ``SpotlightKeywordGenerator``
/// (the plain-text `respond` path, shared with RankBuddy); this type keeps the
/// question-specific brief and the nil-when-empty seam the indexer expects.
enum SpotlightSummarizer {
    /// Whether the on-device model can generate keywords right now.
    static var isAvailable: Bool {
        SpotlightKeywordGenerator.isAvailable
    }

    /// A few topical keywords for a question (e.g. "binary search", "recursion"),
    /// or nil when the model is unavailable, there's no description to read, or
    /// generation fails.
    static func keywords(title: String, language: String?, description: String) async -> [String]? {
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDescription.isEmpty else { return nil }

        let brief = [
            title.isEmpty ? nil : "Title: \(title)",
            language.flatMap { $0.isEmpty ? nil : "Language: \($0.coderPadLanguageDisplayName)" },
            "Description: \(trimmedDescription.prefix(2000))"
        ].compactMap(\.self).joined(separator: "\n")

        let keywords = await SpotlightKeywordGenerator.keywords(from: brief)
        return keywords.isEmpty ? nil : keywords
    }
}
