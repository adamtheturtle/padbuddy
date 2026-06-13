import Foundation
#if canImport(FoundationModels)
    import FoundationModels
#endif

/// Produces a short "what happened" digest of a finished (or in-progress) pad
/// using Apple's on-device FoundationModels. Like ``SavedSearchNamer`` the whole
/// feature is additive: it runs entirely on device (private, no network), is only
/// offered on macOS 26+ with an available system model, and the caller shows
/// nothing when it can't help. The digest summarizes the candidate's submitted
/// code, the languages involved, and the session activity so an interviewer can
/// grasp a pad at a glance without re-reading it. See [[coderpad-pad-mutation-contract]].
enum PadSummarizer {
    /// The most code we feed the model, in characters. A long multi-file project
    /// would blow past the context window and slow generation for no real gain —
    /// a few thousand characters is plenty to characterize an approach.
    private static let maxCodeCharacters = 6000

    /// Whether the on-device model can summarize a pad right now. False on older
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

    /// A few-sentence digest of the pad, or nil if the model is unavailable, the
    /// pad has no code to summarize, or generation fails. Callers keep the rest of
    /// the detail view untouched on nil.
    static func summarize(pad: Pad, files: [CodeFile], events: [PadEvent]) async -> String? {
        #if canImport(FoundationModels)
            if #available(macOS 26, *) {
                return await generate(pad: pad, files: files, events: events)
            }
        #endif
        return nil
    }

    /// The plain-text brief handed to the model: identity, languages, participation,
    /// the event kinds seen, and the (truncated) code. Pure and synchronous so it
    /// can be unit-tested without standing up a model session.
    static func brief(pad: Pad, files: [CodeFile], events: [PadEvent]) -> String {
        var parts: [String] = []
        if !pad.title.isEmpty { parts.append("Title: \(pad.title)") }
        let languages = Set(files.compactMap(\.language).filter { !$0.isEmpty })
            .map { $0.languageDisplayName }
            .sorted()
        if !languages.isEmpty { parts.append("Languages: \(languages.joined(separator: ", "))") }
        if !pad.participants.isEmpty {
            parts.append("Participants: \(pad.participants.count)")
        }
        let eventKinds = Set(events.map { $0.kind.lowercased() }.filter { !$0.isEmpty })
        if !eventKinds.isEmpty {
            parts.append("Session activity: \(eventKinds.sorted().joined(separator: ", "))")
        }
        parts.append("Code:\n\(truncatedCode(files))")
        return parts.joined(separator: "\n")
    }

    /// Concatenates the files with a per-file path header, capped at
    /// `maxCodeCharacters` so a huge project doesn't overflow the context window.
    private static func truncatedCode(_ files: [CodeFile]) -> String {
        var out = ""
        for file in files {
            let header = "// \(file.path ?? file.name)\n"
            if out.count + header.count + file.contents.count > maxCodeCharacters {
                let remaining = maxCodeCharacters - out.count - header.count
                if remaining > 0 {
                    out += header + file.contents.prefix(remaining) + "\n…(truncated)\n"
                }
                break
            }
            out += header + file.contents + "\n"
        }
        return out.isEmpty ? "(no code)" : out
    }
}

#if canImport(FoundationModels)
    @available(macOS 26, *)
    private extension PadSummarizer {
        /// A single field so guided generation hands back clean prose rather than a
        /// preamble ("Here is a summary…") we'd have to strip.
        @Generable
        struct Digest {
            @Guide(description: "Two or three plain sentences summarizing the candidate's approach, "
                + "the languages used, and the session activity. No preamble, no markdown, no bullet points.")
            let summary: String
        }

        static func generate(pad: Pad, files: [CodeFile], events: [PadEvent]) async -> String? {
            guard !files.isEmpty else { return nil }
            guard SystemLanguageModel.default.availability == .available else { return nil }

            let instructions = """
            You summarize coding interview pads for an interviewer reviewing them. Given a brief \
            describing the pad and the candidate's submitted code, write a concise, neutral digest \
            of what the candidate did: the approach taken, the languages involved, and any notable \
            session activity. Use two or three plain sentences, no preamble, no markdown.
            """
            let session = LanguageModelSession(instructions: instructions)
            do {
                let response = try await session.respond(
                    to: brief(pad: pad, files: files, events: events),
                    generating: Digest.self
                )
                let summary = response.content.summary.trimmingCharacters(in: .whitespacesAndNewlines)
                return summary.isEmpty ? nil : summary
            } catch {
                return nil
            }
        }
    }
#endif
