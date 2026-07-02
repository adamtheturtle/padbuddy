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
            return SystemLanguageModel.default.availability == .available
        #else
            return false
        #endif
    }

    /// A short, friendly label built from the search's active filters, or nil if
    /// the model is unavailable, the search has nothing worth naming, or generation
    /// fails. Callers keep the manual field untouched on nil.
    static func suggestName(for search: NamedSearch) async -> String? {
        #if canImport(FoundationModels)
            return await generate(for: search)
        #else
            return nil
        #endif
    }
}

#if canImport(FoundationModels)
    private extension SavedSearchNamer {
        static func generate(for search: NamedSearch) async -> String? {
            let criteria = search.filterDescription
            guard !criteria.isEmpty else { return nil }
            guard SystemLanguageModel.default.availability == .available else { return nil }

            let instructions = """
            You name saved searches in a developer tool for browsing coding interview \
            pads and questions. Given a list of the active filters, produce a concise, \
            human label the user would recognize at a glance. Use Title Case, at most \
            four words, no quotes, and no trailing punctuation. Reply with only the label \
            on a single line - no preamble, explanation, or markdown.
            """
            let session = LanguageModelSession(instructions: instructions)
            do {
                // Plain-text `respond(to:)`, never `@Generable`: the accessor the macro
                // emits is absent on some shipping OS builds and aborts at dyld load. The
                // reply is a single label line we clean here (see `cleanLabel`).
                let response = try await session.respond(to: "Filters: \(criteria)")
                return cleanLabel(response.content)
            } catch {
                return nil
            }
        }

        /// Reduces the model's plain-text reply to a single clean label: the first
        /// non-empty line, with surrounding quotes and trailing sentence punctuation
        /// removed, capped to the field's max length. Nil when nothing usable remains.
        /// Pure and off-main-safe, so it's testable without the model.
        static func cleanLabel(_ reply: String) -> String? {
            let firstLine = reply
                .split(whereSeparator: \.isNewline)
                .first
                .map(String.init) ?? ""
            var name = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
            name = name.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            name = name.trimmingCharacters(in: CharacterSet(charactersIn: " .,:;"))
            guard !name.isEmpty else { return nil }

            return String(name.prefix(NamedSearch.maxNameLength))
        }
    }
#endif
