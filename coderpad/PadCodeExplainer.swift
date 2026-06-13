import Foundation
#if canImport(FoundationModels)
    import FoundationModels
#endif

/// Explains a single code file from a pad in plain language using Apple's
/// on-device FoundationModels. Additive and private like ``SavedSearchNamer`` /
/// ``PadSummarizer``: on-device only, macOS 26+ with an available model, and the
/// caller shows nothing when it can't help. Aimed at an interviewer skimming a
/// candidate's submission in an unfamiliar language.
enum PadCodeExplainer {
    /// The most source we feed the model, in characters, so a very large file
    /// doesn't overflow the context window or stall generation.
    private static let maxCodeCharacters = 6000

    /// Whether the on-device model can explain code right now. See
    /// ``PadSummarizer/isAvailable`` for the conditions.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
            if #available(macOS 26, *) {
                return SystemLanguageModel.default.availability == .available
            }
        #endif
        return false
    }

    /// A short plain-language explanation of what `file` does, or nil if the model
    /// is unavailable, the file is empty, or generation fails.
    static func explain(file: CodeFile) async -> String? {
        #if canImport(FoundationModels)
            if #available(macOS 26, *) {
                return await generate(file: file)
            }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
    @available(macOS 26, *)
    private extension PadCodeExplainer {
        @Generable
        struct Explanation {
            @Guide(description: "A clear explanation of what the code does and the approach it takes, "
                + "in two to four plain sentences. No preamble, no markdown, no code fences.")
            let text: String
        }

        static func generate(file: CodeFile) async -> String? {
            let body = file.contents.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { return nil }
            guard SystemLanguageModel.default.availability == .available else { return nil }

            let language = file.language?.languageDisplayName ?? "code"
            let instructions = """
            You explain source code to an interviewer reviewing a candidate's work. Describe what \
            the code does and the approach it takes, clearly and neutrally, in two to four plain \
            sentences. Do not restate the code line by line, do not use markdown, and do not pass \
            judgement on the candidate.
            """
            let prompt = "Explain this \(language) file named \(file.name):\n\n\(body.prefix(maxCodeCharacters))"
            let session = LanguageModelSession(instructions: instructions)
            do {
                let response = try await session.respond(to: prompt, generating: Explanation.self)
                let text = response.content.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : text
            } catch {
                return nil
            }
        }
    }
#endif
