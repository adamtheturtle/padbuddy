import Foundation
#if canImport(FoundationModels)
    import FoundationModels
#endif

/// Turns a natural-language request ("Python pads from last week", "my draft
/// SQL questions") into a structured ``NamedSearch`` the pad or question list can
/// apply, using Apple's on-device FoundationModels. Additive and private like
/// ``SavedSearchNamer`` — and the inverse of it: that one names a filter set, this
/// one builds one from words. On-device only, macOS 26+ with an available model,
/// and the caller leaves the filters untouched when it returns nil.
enum SearchInterpreter {
    /// An owner the list can filter by, carrying both the email the filter stores
    /// and the display name the user is likely to type. The model is shown names
    /// (people say "Rob Di Marco", not an address), and the interpreter matches its
    /// output against either field before returning the email the chip needs.
    struct OwnerOption: Hashable, Sendable {
        let email: String
        let name: String
    }

    /// Whether the on-device model can interpret a query right now. See
    /// ``PadSummarizer/isAvailable`` for the conditions.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
            if #available(macOS 26, *) {
                return SystemLanguageModel.default.availability == .available
            }
        #endif
        return false
    }

    /// A pad filter set derived from `text`, or nil when the model is unavailable,
    /// the text is empty, or generation fails. `languages`/`owners` are the values
    /// actually present in the list, so the model maps onto real options.
    static func interpretPads(_ text: String, languages: [String], owners: [OwnerOption],
                              teams: [String]) async -> NamedSearch? {
        #if canImport(FoundationModels)
            if #available(macOS 26, *) {
                return await generatePads(text, languages: languages, owners: owners, teams: teams)
            }
        #endif
        return nil
    }

    /// A question filter set derived from `text`, or nil under the same conditions
    /// as ``interpretPads(_:languages:owners:teams:)``.
    static func interpretQuestions(_ text: String, languages: [String], owners: [OwnerOption]) async -> NamedSearch? {
        #if canImport(FoundationModels)
            if #available(macOS 26, *) {
                return await generateQuestions(text, languages: languages, owners: owners)
            }
        #endif
        return nil
    }

    // MARK: - Value resolution (pure, shared with the generated path)

    /// Matches a free-form language onto a value present in the list, comparing
    /// case-insensitively against both the raw codes and their display names. Nil
    /// when nothing matches, so an unknown language simply isn't filtered on.
    static func resolveLanguage(_ raw: String, in languages: [String]) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        if let exact = languages.first(where: { $0.lowercased() == trimmed }) { return exact }
        return languages.first { $0.languageDisplayName.lowercased() == trimmed }
    }

    /// Matches a free-form owner onto an email present in the list and returns that
    /// email. The model usually echoes the person's name ("Rob Di Marco"), so this
    /// matches against the display name as well as the email — by exact match first,
    /// then substring (so "rob" or a partial address still resolves). Nil when
    /// nothing matches.
    static func resolveOwner(_ raw: String, in owners: [OwnerOption]) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        if let exact = owners.first(where: {
            $0.name.lowercased() == trimmed || $0.email.lowercased() == trimmed
        }) {
            return exact.email
        }
        return owners.first {
            $0.name.lowercased().contains(trimmed) || $0.email.lowercased().contains(trimmed)
        }?.email
    }

    /// Matches a free-form team onto a team name present in the list, by exact match
    /// or substring. Nil when nothing matches — so a vague "my team" (no team is
    /// literally named that) sets no team filter rather than guessing one, and never
    /// bleeds into the owner field.
    static func resolveTeam(_ raw: String, in teams: [String]) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        if let exact = teams.first(where: { $0.lowercased() == trimmed }) { return exact }
        return teams.first { $0.lowercased().contains(trimmed) }
    }

    /// Accepts only the pad states the list filters on; maps API synonyms via
    /// ``PadState``. Nil for anything else (including the catch-all `.other`).
    static func resolveState(_ raw: String) -> PadState? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let state = PadState(apiState: trimmed)
        switch state {
        case .active, .ended, .pending: return state
        default: return nil
        }
    }

    /// Normalizes a free-form type to an ``InterviewType`` raw value, or nil.
    static func resolveType(_ raw: String) -> String? {
        InterviewType(rawType: raw.trimmingCharacters(in: .whitespacesAndNewlines))?.rawValue
    }

    /// Matches a free-form range onto one of ``PadDateRange/options``, comparing
    /// case-insensitively. Nil when unrecognized.
    static func resolveDateRange(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        return PadDateRange.options.first { $0 == trimmed }
    }

    /// Accepts only "draft" or "published" for the question draft filter.
    static func resolveDraft(_ raw: String) -> String? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "draft": return "draft"
        case "published": return "published"
        default: return nil
        }
    }

    /// A short, comma-separated list of options to steer the model, capped so a big
    /// org's owner list doesn't dominate the prompt.
    static func optionList(_ values: [String], limit: Int) -> String {
        values.prefix(limit).joined(separator: ", ")
    }
}

#if canImport(FoundationModels)
    @available(macOS 26, *)
    private extension SearchInterpreter {
        @Generable
        struct PadQuery {
            @Guide(description: "Free-text keywords to search pad titles for, or empty if none.")
            let text: String
            @Guide(description: "A language code from the provided list, or empty.")
            let language: String
            @Guide(description: "The name of a single person from the provided owners list, or "
                + "empty. Never put a team name here.")
            let owner: String
            @Guide(description: "A team name from the provided list, or empty. Use this for any "
                + "request about a team or group, not the owner field.")
            let team: String
            @Guide(description: "Pad state: exactly active, ended, or pending, or empty.")
            let state: String
            @Guide(description: "Exactly live or take-home, or empty.")
            let type: String
            @Guide(description: "A relative recency window: today, last 24 hours, last 7 days, "
                + "last 30 days, or last 90 days, or empty.")
            let dateRange: String
        }

        @Generable
        struct QuestionQuery {
            @Guide(description: "Free-text keywords to search question titles for, or empty if none.")
            let text: String
            @Guide(description: "A language code from the provided list, or empty.")
            let language: String
            @Guide(description: "The name of a person from the provided owners list, or empty.")
            let owner: String
            @Guide(description: "Exactly live or take-home, or empty.")
            let type: String
            @Guide(description: "Exactly draft or published, or empty.")
            let draft: String
        }

        static func generatePads(_ text: String, languages: [String], owners: [OwnerOption],
                                 teams: [String]) async -> NamedSearch? {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            guard SystemLanguageModel.default.availability == .available else { return nil }

            let instructions = """
            You translate a user's plain-language request into structured filters for a list of \
            coding interview pads. Fill only the fields the request clearly implies and leave the \
            rest empty. The owner field is for a single named person only; route any team or group \
            request to the team field instead. Languages available: \(optionList(languages, limit: 60)). \
            Owners available: \(optionList(owners.map(\.name), limit: 40)). \
            Teams available: \(optionList(teams, limit: 40)).
            """
            let session = LanguageModelSession(instructions: instructions)
            do {
                let q = try await session.respond(to: trimmed, generating: PadQuery.self).content
                let window = resolveDateRange(q.dateRange).map { PadDateWindow(range: $0) }
                let search = NamedSearch(
                    name: "",
                    search: q.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    stateFilter: resolveState(q.state),
                    languageFilter: resolveLanguage(q.language, in: languages),
                    ownerFilter: resolveOwner(q.owner, in: owners),
                    teamFilter: resolveTeam(q.team, in: teams),
                    typeFilter: resolveType(q.type),
                    updatedWindow: window
                )
                return isMeaningful(search) ? search : nil
            } catch {
                return nil
            }
        }

        static func generateQuestions(_ text: String, languages: [String], owners: [OwnerOption]) async -> NamedSearch? {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            guard SystemLanguageModel.default.availability == .available else { return nil }

            let instructions = """
            You translate a user's plain-language request into structured filters for a list of \
            coding interview questions. Fill only the fields the request clearly implies and leave \
            the rest empty. Languages available: \(optionList(languages, limit: 60)). \
            Owners available: \(optionList(owners.map(\.name), limit: 40)).
            """
            let session = LanguageModelSession(instructions: instructions)
            do {
                let q = try await session.respond(to: trimmed, generating: QuestionQuery.self).content
                let search = NamedSearch(
                    name: "",
                    search: q.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    languageFilter: resolveLanguage(q.language, in: languages),
                    ownerFilter: resolveOwner(q.owner, in: owners),
                    typeFilter: resolveType(q.type),
                    draftFilter: resolveDraft(q.draft)
                )
                return isMeaningful(search) ? search : nil
            } catch {
                return nil
            }
        }

        /// Whether the interpreted search actually constrains anything, so a query
        /// the model couldn't map to any filter doesn't silently "apply" a no-op.
        static func isMeaningful(_ search: NamedSearch) -> Bool {
            !search.filterDescription.isEmpty
        }
    }
#endif
