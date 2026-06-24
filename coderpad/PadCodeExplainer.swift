import Foundation
#if canImport(FoundationModels)
    import FoundationModels
#endif

/// A plain-language explanation of a code file, paired with brief assessments of
/// its quality/readability and the approach's time and space complexity. Returned
/// across the FoundationModels availability boundary, so it stays a simple value
/// type that compiles everywhere.
struct CodeExplanation {
    /// What the code does and the approach it takes.
    let summary: String
    /// How clear and well-written the code is: naming, structure, and style.
    let readability: String
    /// The approach's time and space complexity, in Big O terms, and whether that
    /// is optimal for the problem.
    let optimality: String
}

/// Explains a single code file from a pad in plain language using Apple's
/// on-device FoundationModels. Additive and private like ``SavedSearchNamer`` /
/// ``PadSummarizer``: on-device only, macOS 26+ with an available model, and the
/// caller shows nothing when it can't help. Aimed at an interviewer skimming a
/// candidate's submission in an unfamiliar language, who also wants a quick read
/// on the code's quality and efficiency.
enum PadCodeExplainer {
    /// The most source we feed the model, in characters, so a very large file
    /// doesn't overflow the context window or stall generation.
    private static let maxCodeCharacters = 6000

    /// Whether the on-device model can explain code right now. See
    /// ``PadSummarizer/isAvailable`` for the conditions.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
            if #available(macOS 26, iOS 26, *) {
                return SystemLanguageModel.default.availability == .available
            }
        #endif
        return false
    }

    /// An explanation of what `file` does plus quality and optimality notes, or
    /// nil if the model is unavailable, the file is empty, or generation fails.
    static func explain(file: CodeFile) async -> CodeExplanation? {
        #if canImport(FoundationModels)
            if #available(macOS 26, iOS 26, *) {
                return await generate(file: file)
            }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
    @available(macOS 26, iOS 26, *)
    private extension PadCodeExplainer {
        @Generable
        struct Explanation {
            @Guide(description: "A clear explanation of what the code does and the approach it takes, "
                + "in two to three plain sentences. No preamble, no markdown, no code fences.")
            let summary: String

            @Guide(description: "An assessment of the code's quality and readability, covering naming, "
                + "structure, clarity, and style, in one to two plain sentences. No markdown.")
            let readability: String

            @Guide(description: "The approach's time and space complexity stated in Big O notation "
                + "(for example O(n) time, O(1) space), and whether that is optimal for the problem "
                + "or could be improved, in one to two plain sentences. No markdown.")
            let optimality: String
        }

        static func generate(file: CodeFile) async -> CodeExplanation? {
            let body = file.contents.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { return nil }
            guard SystemLanguageModel.default.availability == .available else { return nil }

            let language = file.language?.languageDisplayName ?? "code"
            let instructions = """
            You explain source code to an interviewer reviewing a candidate's work. First describe \
            what the code does and the approach it takes, clearly and neutrally. Then assess the \
            code's quality and readability, and state the approach's time and space complexity in \
            Big O notation, noting whether that is optimal for the problem or could be improved. \
            Judge the code, not the candidate. Do not restate the code line by line and do not use \
            markdown.
            """
            let prompt = "Explain this \(language) file named \(file.name):\n\n\(body.prefix(maxCodeCharacters))"
            let session = LanguageModelSession(instructions: instructions)
            do {
                let response = try await session.respond(to: prompt, generating: Explanation.self)
                let explanation = CodeExplanation(
                    summary: response.content.summary.trimmingCharacters(in: .whitespacesAndNewlines),
                    readability: response.content.readability.trimmingCharacters(in: .whitespacesAndNewlines),
                    optimality: response.content.optimality.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                return explanation.summary.isEmpty ? nil : explanation
            } catch {
                return nil
            }
        }
    }
#endif
