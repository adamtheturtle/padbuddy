import Foundation
#if canImport(FoundationModels)
    import FoundationModels
#endif

/// Suggests metadata for a question from its text using Apple's on-device
/// FoundationModels: the most fitting language and whether it reads as a live or
/// take-home exercise. Additive and private like ``SavedSearchNamer``: on-device
/// only, macOS 26+ with an available model, suggest-then-confirm (the editor's
/// fields stay fully editable and the user opts in per suggestion).
///
/// Scope note: CoderPad's question API exposes a language and a pad type but no
/// difficulty or free-form tag fields, so those can't be written back and aren't
/// suggested here — only the metadata the editor can actually persist.
enum QuestionTagger {
    /// A suggested set of question metadata. Empty fields mean "no suggestion",
    /// so the editor only fills what the model was confident about.
    struct Suggestion {
        /// A CoderPad language code from ``CoderPadLanguages/pickerOptions``, or nil.
        let language: String?
        /// An ``InterviewType`` raw value ("live" / "take-home"), or nil.
        let type: String?
    }

    /// Whether the on-device model can suggest metadata right now. See
    /// ``PadSummarizer/isAvailable`` for the conditions.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
            if #available(macOS 26, *) {
                return SystemLanguageModel.default.availability == .available
            }
        #endif
        return false
    }

    /// Metadata suggested from the question's text, or nil when the model is
    /// unavailable, there's nothing to read, or generation fails.
    static func suggest(title: String, description: String, instructions: String, solution: String) async -> Suggestion? {
        #if canImport(FoundationModels)
            if #available(macOS 26, *) {
                return await generate(title: title, description: description,
                                      instructions: instructions, solution: solution)
            }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
    @available(macOS 26, *)
    private extension QuestionTagger {
        @Generable
        struct RawSuggestion {
            @Guide(description: "The single most fitting programming language for this question, as a "
                + "lowercase identifier like python3, javascript, java, cpp, go, sql. Empty if unclear.")
            let language: String
            @Guide(description: "Whether this is a real-time interview exercise or an async take-home. "
                + "Exactly \"live\" or \"take-home\", or empty if unclear.")
            let type: String
        }

        static func generate(title: String, description: String,
                             instructions: String, solution: String) async -> Suggestion? {
            let brief = [
                title.isEmpty ? nil : "Title: \(title)",
                description.isEmpty ? nil : "Description: \(description)",
                instructions.isEmpty ? nil : "Candidate instructions: \(instructions)",
                solution.isEmpty ? nil : "Solution: \(solution.prefix(2000))"
            ].compactMap(\.self).joined(separator: "\n")
            guard !brief.isEmpty else { return nil }
            guard SystemLanguageModel.default.availability == .available else { return nil }

            let instructionsPrompt = """
            You categorize coding interview questions. Given a question's text, identify the single \
            most fitting programming language (as a lowercase code such as python3, javascript, java, \
            cpp, go, sql) and whether it reads as a real-time "live" exercise or an async "take-home". \
            Leave a field empty when you are unsure rather than guessing.
            """
            let session = LanguageModelSession(instructions: instructionsPrompt)
            do {
                let response = try await session.respond(to: brief, generating: RawSuggestion.self)
                return Suggestion(
                    language: resolveLanguage(response.content.language),
                    type: resolveType(response.content.type)
                )
            } catch {
                return nil
            }
        }

        /// Maps a free-form model language onto a known CoderPad picker code,
        /// matching case-insensitively against both the codes and their display
        /// names so "Python"/"python"/"python3" all resolve. Nil when unrecognized.
        static func resolveLanguage(_ raw: String) -> String? {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !trimmed.isEmpty else { return nil }
            if let exact = CoderPadLanguages.pickerOptions.first(where: { $0.lowercased() == trimmed }) {
                return exact
            }
            return CoderPadLanguages.pickerOptions.first {
                $0.languageDisplayName.lowercased() == trimmed
            }
        }

        /// Normalizes the model's type to a valid ``InterviewType`` raw value, or nil.
        static func resolveType(_ raw: String) -> String? {
            InterviewType(rawType: raw.trimmingCharacters(in: .whitespacesAndNewlines))?.rawValue
        }
    }
#endif
