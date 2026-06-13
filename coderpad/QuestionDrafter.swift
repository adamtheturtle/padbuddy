import Foundation
#if canImport(FoundationModels)
    import FoundationModels
#endif

/// Drafts an interview question from a short prompt using Apple's on-device
/// FoundationModels. Additive and private like ``SavedSearchNamer``: on-device
/// only, macOS 26+ with an available model, opt-in, and every field it returns is
/// a starting point the author reviews and edits before saving — nothing is
/// persisted automatically.
enum QuestionDrafter {
    /// A drafted question. Any field may be empty when the model had nothing useful
    /// to offer for it; the editor fills only the non-empty ones.
    struct Draft {
        let title: String
        let description: String
        let instructions: String
        let solution: String
    }

    /// Whether the on-device model can draft a question right now. See
    /// ``PadSummarizer/isAvailable`` for the conditions.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
            if #available(macOS 26, *) {
                return SystemLanguageModel.default.availability == .available
            }
        #endif
        return false
    }

    /// A drafted question for `prompt` in `language`, or nil when the model is
    /// unavailable, the prompt is empty, or generation fails.
    static func draft(prompt: String, language: String) async -> Draft? {
        #if canImport(FoundationModels)
            if #available(macOS 26, *) {
                return await generate(prompt: prompt, language: language)
            }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
    @available(macOS 26, *)
    private extension QuestionDrafter {
        @Generable
        struct RawDraft {
            @Guide(description: "A short, specific question title, at most eight words. No quotes.")
            let title: String
            @Guide(description: "A one or two sentence summary of the problem for the interviewer.")
            let description: String
            @Guide(description: "Clear candidate-facing instructions: what to build and any constraints. "
                + "Plain prose, no markdown headers.")
            let instructions: String
            @Guide(description: "A correct reference solution in the requested language, as plain source code.")
            let solution: String
        }

        static func generate(prompt: String, language: String) async -> Draft? {
            let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            guard SystemLanguageModel.default.availability == .available else { return nil }

            let languageName = language.languageDisplayName
            let modelInstructions = """
            You help interviewers author coding interview questions. Given a brief description and a \
            target language, draft a complete question: a concise title, a short interviewer-facing \
            description, clear candidate instructions, and a correct reference solution in the target \
            language. Keep it self-contained and unambiguous.
            """
            let session = LanguageModelSession(instructions: modelInstructions)
            do {
                let response = try await session.respond(
                    to: "Target language: \(languageName)\nBrief: \(trimmed)",
                    generating: RawDraft.self
                )
                let draft = response.content
                return Draft(
                    title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    description: draft.description.trimmingCharacters(in: .whitespacesAndNewlines),
                    instructions: draft.instructions.trimmingCharacters(in: .whitespacesAndNewlines),
                    solution: draft.solution.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            } catch {
                return nil
            }
        }
    }
#endif
