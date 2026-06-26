import Foundation
#if canImport(FoundationModels)
    import FoundationModels
#endif

#if canImport(FoundationModels)
    @available(macOS 26, iOS 26, *)
    extension SearchInterpreter {
        /// Every field is optional so the model can — and is told to — omit anything
        /// the request doesn't name. The small on-device model fills non-optional
        /// String fields with a guessed value rather than an empty string, which
        /// over-constrained the list (the raw query landed in `text` and unrelated
        /// language/owner/team/type/date filters were invented); a nullable property
        /// it will readily leave nil.
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
                let query = try await session.respond(to: trimmed, generating: PadQuery.self).content
                let range = groundDateRange(resolveDateRange(query.dateRange ?? ""), query: trimmed)
                let language = groundLanguage(resolveLanguage(query.language ?? "", in: languages), query: trimmed)
                let owner = groundOwner(resolveOwner(query.owner ?? "", in: owners), query: trimmed, owners: owners)
                let team = groundTeam(resolveTeam(query.team ?? "", in: teams), query: trimmed)
                let ownerName = owners.first { $0.email == owner }?.name ?? ""
                let text = groundText(query.text ?? "", languages: languages, ownerName: ownerName, team: team ?? "")
                let search = NamedSearch(
                    name: "",
                    search: text.trimmingCharacters(in: .whitespacesAndNewlines),
                    stateFilter: groundState(resolveState(query.state ?? ""), query: trimmed),
                    languageFilter: language,
                    ownerFilter: owner,
                    teamFilter: team,
                    typeFilter: groundType(resolveType(query.type ?? ""), query: trimmed),
                    updatedWindow: range.map { DateWindow(range: $0) }
                )
                return isMeaningful(search) ? search : nil
            } catch {
                return nil
            }
        }

        static func generateQuestions(_ text: String, languages: [String],
                                      owners: [OwnerOption]) async -> NamedSearch? {
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
                let query = try await session.respond(to: trimmed, generating: QuestionQuery.self).content
                let language = groundLanguage(resolveLanguage(query.language ?? "", in: languages), query: trimmed)
                let owner = groundOwner(resolveOwner(query.owner ?? "", in: owners), query: trimmed, owners: owners)
                let ownerName = owners.first { $0.email == owner }?.name ?? ""
                let text = groundText(query.text ?? "", languages: languages, ownerName: ownerName, team: "")
                let search = NamedSearch(
                    name: "",
                    search: text.trimmingCharacters(in: .whitespacesAndNewlines),
                    languageFilter: language,
                    ownerFilter: owner,
                    typeFilter: groundType(resolveType(query.type ?? ""), query: trimmed),
                    draftFilter: groundDraft(resolveDraft(query.draft ?? ""), query: trimmed)
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
