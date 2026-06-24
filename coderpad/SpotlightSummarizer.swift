import Foundation
#if canImport(FoundationModels)
    import FoundationModels
#endif

/// Generates a handful of concise search keywords for a question from its text,
/// using Apple's on-device FoundationModels, so the Spotlight index surfaces it
/// for terms that don't appear verbatim in its title. Additive and private like
/// ``SavedSearchNamer``: on-device only, macOS 26+ with an available model, and
/// it rides on top of the existing **opt-in** Spotlight indexing — nothing new is
/// indexed that wasn't already, the keywords just enrich items the user chose to
/// index. See ``SpotlightIndexer``.
enum SpotlightSummarizer {
    /// Whether the on-device model can generate keywords right now. See
    /// ``PadSummarizer/isAvailable`` for the conditions.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
            if #available(macOS 26, iOS 26, *) {
                return SystemLanguageModel.default.availability == .available
            }
        #endif
        return false
    }

    /// A few topical keywords for a question (e.g. "binary search", "recursion"),
    /// or nil when the model is unavailable, there's no description to read, or
    /// generation fails.
    static func keywords(title: String, language: String?, description: String) async -> [String]? {
        #if canImport(FoundationModels)
            if #available(macOS 26, iOS 26, *) {
                return await generate(title: title, language: language, description: description)
            }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
    @available(macOS 26, iOS 26, *)
    private extension SpotlightSummarizer {
        @Generable
        struct Keywords {
            @Guide(description: "Three to six short topical search keywords for the question, such as "
                + "data structure or algorithm names. Lowercase, comma-separated, no sentences.")
            let keywords: String
        }

        static func generate(title: String, language: String?, description: String) async -> [String]? {
            let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedDescription.isEmpty else { return nil }
            guard SystemLanguageModel.default.availability == .available else { return nil }

            let brief = [
                title.isEmpty ? nil : "Title: \(title)",
                language.flatMap { $0.isEmpty ? nil : "Language: \($0.languageDisplayName)" },
                "Description: \(trimmedDescription.prefix(2000))"
            ].compactMap(\.self).joined(separator: "\n")

            let instructions = """
            You generate concise search keywords for coding interview questions so they can be found \
            by topic. Return three to six short, lowercase keywords (data structures, algorithms, or \
            problem themes), comma-separated. No sentences, no explanations.
            """
            let session = LanguageModelSession(instructions: instructions)
            do {
                let response = try await session.respond(to: brief, generating: Keywords.self)
                let parsed = response.content.keywords
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                return parsed.isEmpty ? nil : parsed
            } catch {
                return nil
            }
        }
    }
#endif
