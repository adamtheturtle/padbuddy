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

    // MARK: - Grounding (reject model values the query doesn't support)

    /// The small on-device model tends to fill fields the request never mentions —
    /// grabbing the first option from a list, or echoing the whole query into the
    /// free-text search — which over-constrains the list to nothing. These pure
    /// checks keep a model-proposed value only when the user's query actually
    /// supports it, turning the model into a candidate generator that testable code
    /// vets. Shared with the generated path and exercised directly in tests.

    /// Lowercased alphanumeric word tokens of `text`, for whole-word comparison
    /// against the query (so "lin" doesn't match inside "linked").
    static func tokens(_ text: String) -> Set<String> {
        Set(text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty })
    }

    /// Words that name a filter concept rather than a pad or question title, so they
    /// must never survive into the free-text search. Covers list nouns, connectors,
    /// and the state/type/recency vocabulary the model otherwise leaves in `text`.
    static let filterStopWords: Set<String> = [
        "pad", "pads", "question", "questions", "interview", "interviews",
        "by", "from", "the", "a", "an", "of", "in", "on", "for", "with", "and",
        "my", "me", "show", "find", "all", "owned", "created", "made",
        "active", "ended", "pending", "started", "finished", "open", "closed",
        "live", "take", "home", "takehome", "draft", "published",
        "today", "yesterday", "last", "recent", "recently", "past", "this",
        "day", "days", "week", "weeks", "month", "months", "hour", "hours"
    ]

    /// Keeps a resolved language only when the query actually names it, so the
    /// model's habit of grabbing the first option doesn't apply a language the user
    /// never typed. Accepts the word tokens of both the code and its display name —
    /// so "python" matches code "python3" (display name "Python 3") and "c++" matches
    /// "cpp" (display name "C++") — while pure-digit tokens are dropped so a stray
    /// number in the query ("top 3 pads") can't match a versioned code.
    static func groundLanguage(_ code: String?, query: String) -> String? {
        guard let code else { return nil }
        let accepted = tokens(code).union(tokens(code.languageDisplayName))
            .filter { !$0.allSatisfy(\.isNumber) }
        return tokens(query).isDisjoint(with: accepted) ? nil : code
    }

    /// Keeps a resolved owner email only when the query names that person — any word
    /// of their display name (3+ characters, so initials don't false-match) or the
    /// email's local part appearing as a whole query token.
    static func groundOwner(_ email: String?, query: String, owners: [OwnerOption]) -> String? {
        guard let email else { return nil }
        let queryTokens = tokens(query)
        let name = owners.first { $0.email == email }?.name ?? ""
        let nameTokens = tokens(name).filter { $0.count >= 3 }
        if !queryTokens.isDisjoint(with: nameTokens) { return email }
        let local = email.split(separator: "@").first.map { String($0).lowercased() } ?? ""
        return queryTokens.contains(local) ? email : nil
    }

    /// Keeps a resolved team only when the query names it (any team word, 3+ chars).
    static func groundTeam(_ team: String?, query: String) -> String? {
        guard let team else { return nil }
        let teamTokens = tokens(team).filter { $0.count >= 3 }
        return tokens(query).isDisjoint(with: teamTokens) ? nil : team
    }

    /// Keeps a resolved pad state only when the query uses a word for it, so the
    /// model can't attach a status the request never mentioned.
    static func groundState(_ state: PadState?, query: String) -> PadState? {
        guard let state else { return nil }
        let triggers: Set<String>
        switch state {
        case .active: triggers = ["active", "running", "started", "ongoing", "open", "current"]
        case .ended: triggers = ["ended", "finished", "done", "completed", "closed", "past", "old"]
        case .pending: triggers = ["pending", "scheduled", "upcoming", "unstarted"]
        default: return nil
        }
        return tokens(query).isDisjoint(with: triggers) ? nil : state
    }

    /// Keeps a resolved interview type only when the query names it. "take-home" is
    /// matched as a phrase too, since it doesn't tokenize to a single word.
    static func groundType(_ type: String?, query: String) -> String? {
        guard let type else { return nil }
        let queryTokens = tokens(query)
        switch type {
        case "live": return queryTokens.contains("live") ? type : nil
        case "take-home":
            let lower = query.lowercased()
            let named = queryTokens.contains("takehome") || queryTokens.contains("homework")
                || lower.contains("take-home") || lower.contains("take home")
            return named ? type : nil
        default: return nil
        }
    }

    /// Keeps a resolved draft status only when the query names it.
    static func groundDraft(_ draft: String?, query: String) -> String? {
        guard let draft else { return nil }
        let queryTokens = tokens(query)
        switch draft {
        case "draft": return queryTokens.contains("draft") || queryTokens.contains("drafts")
            || queryTokens.contains("unpublished") ? draft : nil
        case "published": return queryTokens.contains("published") || queryTokens.contains("public") ? draft : nil
        default: return nil
        }
    }

    /// Keeps a resolved date window only when the query mentions a time frame.
    static func groundDateRange(_ range: String?, query: String) -> String? {
        guard let range else { return nil }
        let dateWords: Set<String> = [
            "today", "yesterday", "week", "weeks", "month", "months", "day", "days",
            "hour", "hours", "recent", "recently", "last", "past", "this",
            "24", "7", "30", "90", "year", "years"
        ]
        return tokens(query).isDisjoint(with: dateWords) ? nil : range
    }

    /// Strips the model's free-text down to genuine title keywords: drops filter
    /// concept words, every provided language's code and display name, and the words
    /// of the matched owner and team. So a query the model echoes wholesale ("pads
    /// by rob di marco") collapses to empty and the structured filters do the work,
    /// while a real topic ("binary search") survives.
    static func groundText(_ raw: String, languages: [String],
                           ownerName: String, team: String) -> String {
        var drop = filterStopWords
        for language in languages {
            drop.formUnion(tokens(language))
            drop.formUnion(tokens(language.languageDisplayName))
        }
        drop.formUnion(tokens(ownerName))
        drop.formUnion(tokens(team))
        let kept = raw.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .map(String.init)
            .filter { word in
                let key = word.lowercased().filter { $0.isLetter || $0.isNumber }
                return !key.isEmpty && !drop.contains(key)
            }
        return kept.joined(separator: " ")
    }
}

#if canImport(FoundationModels)
    @available(macOS 26, *)
    private extension SearchInterpreter {
        // Every field is optional so the model can — and is told to — omit anything
        // the request doesn't name. The small on-device model fills non-optional
        // String fields with a guessed value rather than an empty string, which
        // over-constrained the list (the raw query landed in `text` and unrelated
        // language/owner/team/type/date filters were invented); a nullable property
        // it will readily leave nil.
        @Generable
        struct PadQuery {
            @Guide(description: "Only real title keywords to search for, and only when the request "
                + "names a topic that is not a language, person, team, state, or date. Otherwise nil. "
                + "Never echo the whole request here.")
            let text: String?
            @Guide(description: "A language code from the provided list, only when the request names "
                + "a language. Otherwise nil.")
            let language: String?
            @Guide(description: "The name of a single person from the provided owners list, only when "
                + "the request names a person. Never a team. Otherwise nil.")
            let owner: String?
            @Guide(description: "A team name from the provided list, only when the request names a "
                + "team or group. Never put a person here. Otherwise nil.")
            let team: String?
            @Guide(description: "Exactly active, ended, or pending, only when the request mentions "
                + "pad status. Otherwise nil.")
            let state: String?
            @Guide(description: "Exactly live or take-home, only when the request mentions interview "
                + "type. Otherwise nil.")
            let type: String?
            @Guide(description: "A recency window: today, last 24 hours, last 7 days, last 30 days, "
                + "or last 90 days, only when the request mentions a time frame. Otherwise nil.")
            let dateRange: String?
        }

        @Generable
        struct QuestionQuery {
            @Guide(description: "Only real title keywords to search for, and only when the request "
                + "names a topic that is not a language, person, type, or draft status. Otherwise "
                + "nil. Never echo the whole request here.")
            let text: String?
            @Guide(description: "A language code from the provided list, only when the request names "
                + "a language. Otherwise nil.")
            let language: String?
            @Guide(description: "The name of a person from the provided owners list, only when the "
                + "request names a person. Otherwise nil.")
            let owner: String?
            @Guide(description: "Exactly live or take-home, only when the request mentions interview "
                + "type. Otherwise nil.")
            let type: String?
            @Guide(description: "Exactly draft or published, only when the request mentions draft "
                + "status. Otherwise nil.")
            let draft: String?
        }

        static func generatePads(_ text: String, languages: [String], owners: [OwnerOption],
                                 teams: [String]) async -> NamedSearch? {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            guard SystemLanguageModel.default.availability == .available else { return nil }

            let instructions = """
            You translate a user's plain-language request into structured filters for a list of \
            coding interview pads. Set only the fields the request explicitly names and leave every \
            other field nil — do not guess or fill a field the request doesn't mention. Most \
            requests name just one or two fields. The owner field is for a single named person only; \
            route any team or group request to the team field instead. \
            Languages available: \(optionList(languages, limit: 60)). \
            Owners available: \(optionList(owners.map(\.name), limit: 40)). \
            Teams available: \(optionList(teams, limit: 40)).
            """
            let session = LanguageModelSession(instructions: instructions)
            do {
                let q = try await session.respond(to: trimmed, generating: PadQuery.self).content
                let range = groundDateRange(resolveDateRange(q.dateRange ?? ""), query: trimmed)
                let language = groundLanguage(resolveLanguage(q.language ?? "", in: languages), query: trimmed)
                let owner = groundOwner(resolveOwner(q.owner ?? "", in: owners), query: trimmed, owners: owners)
                let team = groundTeam(resolveTeam(q.team ?? "", in: teams), query: trimmed)
                let ownerName = owners.first { $0.email == owner }?.name ?? ""
                let text = groundText(q.text ?? "", languages: languages, ownerName: ownerName, team: team ?? "")
                let search = NamedSearch(
                    name: "",
                    search: text.trimmingCharacters(in: .whitespacesAndNewlines),
                    stateFilter: groundState(resolveState(q.state ?? ""), query: trimmed),
                    languageFilter: language,
                    ownerFilter: owner,
                    teamFilter: team,
                    typeFilter: groundType(resolveType(q.type ?? ""), query: trimmed),
                    updatedWindow: range.map { PadDateWindow(range: $0) }
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
            coding interview questions. Set only the fields the request explicitly names and leave \
            every other field nil — do not guess or fill a field the request doesn't mention. Most \
            requests name just one or two fields. Languages available: \(optionList(languages, limit: 60)). \
            Owners available: \(optionList(owners.map(\.name), limit: 40)).
            """
            let session = LanguageModelSession(instructions: instructions)
            do {
                let q = try await session.respond(to: trimmed, generating: QuestionQuery.self).content
                let language = groundLanguage(resolveLanguage(q.language ?? "", in: languages), query: trimmed)
                let owner = groundOwner(resolveOwner(q.owner ?? "", in: owners), query: trimmed, owners: owners)
                let ownerName = owners.first { $0.email == owner }?.name ?? ""
                let text = groundText(q.text ?? "", languages: languages, ownerName: ownerName, team: "")
                let search = NamedSearch(
                    name: "",
                    search: text.trimmingCharacters(in: .whitespacesAndNewlines),
                    languageFilter: language,
                    ownerFilter: owner,
                    typeFilter: groundType(resolveType(q.type ?? ""), query: trimmed),
                    draftFilter: groundDraft(resolveDraft(q.draft ?? ""), query: trimmed)
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
