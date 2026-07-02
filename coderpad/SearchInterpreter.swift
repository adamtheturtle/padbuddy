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
    struct OwnerOption: Hashable {
        let email: String
        let name: String
    }

    /// Whether the on-device model can interpret a query right now. See
    /// ``PadSummarizer/isAvailable`` for the conditions.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
            return SystemLanguageModel.default.availability == .available
        #else
            return false
        #endif
    }

    /// A pad filter set derived from `text`, or nil when the model is unavailable,
    /// the text is empty, or generation fails. `languages`/`owners` are the values
    /// actually present in the list, so the model maps onto real options.
    static func interpretPads(_ text: String, languages: [String], owners: [OwnerOption],
                              teams: [String]) async -> NamedSearch? {
        #if canImport(FoundationModels)
            return await generatePads(text, languages: languages, owners: owners, teams: teams)
        #else
            return nil
        #endif
    }

    /// A question filter set derived from `text`, or nil under the same conditions
    /// as ``interpretPads(_:languages:owners:teams:)``.
    static func interpretQuestions(_ text: String, languages: [String], owners: [OwnerOption]) async -> NamedSearch? {
        #if canImport(FoundationModels)
            return await generateQuestions(text, languages: languages, owners: owners)
        #else
            return nil
        #endif
    }

    // MARK: - Value resolution (pure, shared with the generated path)

    /// Matches a free-form language onto a value present in the list, comparing
    /// case-insensitively against both the raw codes and their display names. Nil
    /// when nothing matches, so an unknown language simply isn't filtered on.
    static func resolveLanguage(_ raw: String, in languages: [String]) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        if let exact = languages.first(where: { $0.lowercased() == trimmed }) { return exact }
        return languages.first { $0.coderPadLanguageDisplayName.lowercased() == trimmed }
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
        case "draft": "draft"
        case "published": "published"
        default: nil
        }
    }

    /// A short, comma-separated list of options to steer the model, capped so a big
    /// org's owner list doesn't dominate the prompt. Delegates to the shared
    /// ``SearchGrounding`` core.
    static func optionList(_ values: [String], limit: Int) -> String {
        SearchGrounding.optionList(values, limit: limit)
    }

    // MARK: - Grounding (reject model values the query doesn't support)

    // The small on-device model tends to fill fields the request never mentions —
    // grabbing the first option from a list, or echoing the whole query into the
    // free-text search — which over-constrains the list to nothing. These pure
    // checks keep a model-proposed value only when the user's query actually
    // supports it, turning the model into a candidate generator that testable code
    // vets. Shared with the generated path and exercised directly in tests.

    /// Lowercased alphanumeric word tokens of `text`, for whole-word comparison
    /// against the query (so "lin" doesn't match inside "linked"). Delegates to the
    /// shared ``SearchGrounding`` core.
    static func tokens(_ text: String) -> Set<String> {
        SearchGrounding.tokens(text)
    }

    /// Words that name a filter concept rather than a pad or question title, so they
    /// must never survive into the free-text search. Now the shared ``SearchGrounding``
    /// stop-word set — a superset of the old app list; the extra words only ever strip
    /// genuine filter concepts, never real titles.
    static let filterStopWords = SearchGrounding.filterStopWords

    /// Keeps a resolved language only when the query actually names it, so the
    /// model's habit of grabbing the first option doesn't apply a language the user
    /// never typed. Accepts the word tokens of both the code and its display name —
    /// so "python" matches code "python3" (display name "Python 3") and "c++" matches
    /// "cpp" (display name "C++") — while pure-digit tokens are dropped so a stray
    /// number in the query ("top 3 pads") can't match a versioned code.
    static func groundLanguage(_ code: String?, query: String) -> String? {
        guard let code else { return nil }

        let accepted = tokens(code).union(tokens(code.coderPadLanguageDisplayName))
            .filter { !$0.allSatisfy(\.isNumber) }
        return tokens(query).isDisjoint(with: accepted) ? nil : code
    }

    /// Keeps a resolved owner email only when the query names that person — any word
    /// of their display name (2+ characters, so single-letter initials don't
    /// false-match but real short names like "Jo" or "Li" still do) or the email's
    /// local part appearing as a whole query token. Matching is whole-token, so a
    /// short name can't match inside a longer query word.
    static func groundOwner(_ email: String?, query: String, owners: [OwnerOption]) -> String? {
        guard let email else { return nil }

        let queryTokens = tokens(query)
        let name = owners.first { $0.email == email }?.name ?? ""
        let nameTokens = tokens(name).filter { $0.count >= 2 }
        if !queryTokens.isDisjoint(with: nameTokens) { return email }
        let local = email.split(separator: "@").first.map { String($0).lowercased() } ?? ""
        return queryTokens.contains(local) ? email : nil
    }

    /// Keeps a resolved team only when the query names it (any team word, 2+ chars,
    /// so single-letter tokens don't false-match but short team names still do).
    static func groundTeam(_ team: String?, query: String) -> String? {
        guard let team else { return nil }

        let teamTokens = tokens(team).filter { $0.count >= 2 }
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
        SearchGrounding.groundDateRange(range, query: query)
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
            drop.formUnion(tokens(language.coderPadLanguageDisplayName))
        }
        drop.formUnion(tokens(ownerName))
        drop.formUnion(tokens(team))
        return SearchGrounding.groundText(raw: raw, drop: drop)
    }
}
