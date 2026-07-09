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
/// on-device FoundationModels. Additive and private like ``PadSummarizer``:
/// on-device only, macOS 26+ with an available model, and the
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
            return SystemLanguageModel.default.availability == .available
        #else
            return false
        #endif
    }

    /// An explanation of what `file` does plus quality and optimality notes, or
    /// nil if the model is unavailable, the file is empty, or generation fails.
    static func explain(file: CodeFile) async -> CodeExplanation? {
        #if canImport(FoundationModels)
            return await generate(file: file)
        #else
            return nil
        #endif
    }
}

#if canImport(FoundationModels)
    private extension PadCodeExplainer {
        static func generate(file: CodeFile) async -> CodeExplanation? {
            let body = file.contents.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { return nil }
            guard SystemLanguageModel.default.availability == .available else { return nil }

            let language = file.language?.coderPadLanguageDisplayName ?? "code"
            let instructions = """
            You explain source code to an interviewer reviewing a candidate's work. First describe \
            what the code does and the approach it takes, clearly and neutrally. Then assess the \
            code's quality and readability, and state the approach's time and space complexity in \
            Big O notation, noting whether that is optimal for the problem or could be improved. \
            Judge the code, not the candidate. Do not restate the code line by line and do not use \
            markdown.

            Reply with exactly these three labeled sections and nothing else:
            SUMMARY: what the code does and the approach it takes, in two to three plain sentences.
            READABILITY: the code's quality and readability - naming, structure, clarity, style - \
            in one to two plain sentences.
            OPTIMALITY: the time and space complexity in Big O notation (for example O(n) time, \
            O(1) space) and whether that is optimal, in one to two plain sentences.
            """
            let prompt = "Explain this \(language) file named \(file.name):\n\n\(body.prefix(maxCodeCharacters))"
            let session = LanguageModelSession(instructions: instructions)
            do {
                // Plain-text `respond(to:)`, never `@Generable` (its emitted accessor aborts
                // at dyld load on some OS builds); the labeled reply is parsed back here.
                let response = try await session.respond(to: prompt)
                return parseExplanation(response.content)
            } catch {
                return nil
            }
        }

        /// Reconstructs the three-part explanation from the model's labeled reply. Nil when
        /// the summary is missing, mirroring the old "empty summary means nothing usable"
        /// guard. Pure and off-main-safe, so it's testable without the model.
        static func parseExplanation(_ reply: String) -> CodeExplanation? {
            let sections = OnDeviceModelParsing.labeledSections(
                reply, labels: ["SUMMARY", "READABILITY", "OPTIMALITY"]
            )
            let summary = sections["SUMMARY"] ?? ""
            guard !summary.isEmpty else { return nil }

            return CodeExplanation(
                summary: summary,
                readability: sections["READABILITY"] ?? "",
                optimality: sections["OPTIMALITY"] ?? ""
            )
        }
    }
#endif
