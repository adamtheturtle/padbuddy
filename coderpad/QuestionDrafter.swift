import Foundation
#if canImport(FoundationModels)
    import FoundationModels
#endif

/// Drafts an interview question from a short prompt using Apple's on-device
/// FoundationModels. Additive and private like ``PadCodeExplainer``: on-device
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
            return SystemLanguageModel.default.availability == .available
        #else
            return false
        #endif
    }

    /// A drafted question for `prompt` in `language`, or nil when the model is
    /// unavailable, the prompt is empty, or generation fails.
    static func draft(prompt: String, language: String) async -> Draft? {
        #if canImport(FoundationModels)
            return await generate(prompt: prompt, language: language)
        #else
            return nil
        #endif
    }
}

#if canImport(FoundationModels)
    private extension QuestionDrafter {
        static func generate(prompt: String, language: String) async -> Draft? {
            let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            guard SystemLanguageModel.default.availability == .available else { return nil }

            let languageName = language.coderPadLanguageDisplayName
            let modelInstructions = """
            You help interviewers author coding interview questions. Given a brief description and a \
            target language, draft a complete question: a concise title, a short interviewer-facing \
            description, clear candidate instructions, and a correct reference solution in the target \
            language. Keep it self-contained and unambiguous.

            Reply with exactly these four labeled sections, in this order, and nothing else:
            TITLE: a short, specific title, at most eight words, no quotes.
            DESCRIPTION: a one or two sentence summary of the problem for the interviewer.
            INSTRUCTIONS: clear candidate-facing instructions - what to build and any constraints, \
            as plain prose.
            SOLUTION: a correct reference solution in \(languageName), as plain source code (this \
            section may span multiple lines).
            """
            let session = LanguageModelSession(instructions: modelInstructions)
            do {
                // Plain-text `respond(to:)`, never `@Generable` (its emitted accessor aborts
                // at dyld load on some OS builds); the labeled reply is parsed back here.
                let response = try await session.respond(to: "Target language: \(languageName)\nBrief: \(trimmed)")
                return parseDraft(response.content)
            } catch {
                return nil
            }
        }

        /// Reconstructs the drafted question from the model's labeled reply. Any field the
        /// model omitted comes back empty, which the editor treats as "nothing to fill" (the
        /// same contract as before). Nil only when nothing usable was produced. Pure and
        /// off-main-safe, so it's testable without the model.
        static func parseDraft(_ reply: String) -> Draft? {
            let sections = OnDeviceModelParsing.labeledSections(
                reply, labels: ["TITLE", "DESCRIPTION", "INSTRUCTIONS", "SOLUTION"]
            )
            let draft = Draft(
                title: sections["TITLE"] ?? "",
                description: sections["DESCRIPTION"] ?? "",
                instructions: sections["INSTRUCTIONS"] ?? "",
                solution: sections["SOLUTION"] ?? ""
            )
            let hasContent = ![draft.title, draft.description, draft.instructions, draft.solution]
                .allSatisfy(\.isEmpty)
            return hasContent ? draft : nil
        }
    }
#endif
