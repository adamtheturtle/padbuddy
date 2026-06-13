import Foundation
#if canImport(FoundationModels)
    import FoundationModels
#endif

/// Suggests a short, human label for a saved search using Apple's on-device
/// FoundationModels. The whole feature is additive: it runs entirely on device
/// (private, no network), is only offered on macOS 26+ with an available system
/// model, and every caller falls back to manual entry when it can't help.
enum SavedSearchNamer {
    /// Whether the on-device model can name a search right now. False on older
    /// macOS, when Apple Intelligence is off or unsupported, or while the model is
    /// still downloading. Callers use this to decide whether to show the affordance.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
            if #available(macOS 26, *) {
                return SystemLanguageModel.default.availability == .available
            }
        #endif
        return false
    }

    /// A short, friendly label built from the search's active filters, or nil if
    /// the model is unavailable, the search has nothing worth naming, or generation
    /// fails. Callers keep the manual field untouched on nil.
    static func suggestName(for search: NamedSearch) async -> String? {
        #if canImport(FoundationModels)
            if #available(macOS 26, *) {
                return await generate(for: search)
            }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
    @available(macOS 26, *)
    private extension SavedSearchNamer {
        /// A single field so guided generation hands back a clean label rather than
        /// prose we'd have to strip quotes and punctuation out of.
        @Generable
        struct Suggestion {
            @Guide(description: "A concise Title Case label of at most four words, no quotes or trailing punctuation")
            let name: String
        }

        static func generate(for search: NamedSearch) async -> String? {
            let criteria = search.filterDescription
            guard !criteria.isEmpty else { return nil }
            guard SystemLanguageModel.default.availability == .available else { return nil }

            let instructions = """
            You name saved searches in a developer tool for browsing coding interview \
            pads and questions. Given a list of the active filters, produce a concise, \
            human label the user would recognize at a glance. Use Title Case, at most \
            four words, no quotes, and no trailing punctuation.
            """
            let session = LanguageModelSession(instructions: instructions)
            do {
                let response = try await session.respond(
                    to: "Filters: \(criteria)",
                    generating: Suggestion.self
                )
                let name = response.content.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return nil }
                return String(name.prefix(NamedSearch.maxNameLength))
            } catch {
                return nil
            }
        }
    }
#endif
