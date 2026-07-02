import Foundation
#if canImport(FoundationModels)
    import FoundationModels
#endif

#if canImport(FoundationModels)
    extension SearchInterpreter {
        static func generatePads(_ text: String, languages: [String], owners: [OwnerOption],
                                 teams: [String]) async -> NamedSearch? {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            guard SystemLanguageModel.default.availability == .available else { return nil }

            let instructions = """
            You translate a user's plain-language request into structured filters for a list of \
            coding interview pads. Set only the fields the request explicitly names and leave every \
            other field out — do not guess or fill a field the request doesn't mention. Most \
            requests name just one or two fields. The owner field is for a single named person only; \
            route any team or group request to the team field instead. \
            Languages available: \(optionList(languages, limit: 60)). \
            Owners available: \(optionList(owners.map(\.name), limit: 40)). \
            Teams available: \(optionList(teams, limit: 40)).

            Reply with only these lines, one field per line, and omit any field the request does \
            not name (or write its value as nil):
            text: real title keywords only, never the whole request, and never a language/person/team/state/date
            language: a language from the list
            owner: a single person's name from the list
            team: a team name from the list
            state: active, ended, or pending
            type: live or take-home
            dateRange: today, last 24 hours, last 7 days, last 30 days, or last 90 days
            """
            let session = LanguageModelSession(instructions: instructions)
            do {
                // Plain-text `respond(to:)`, never `@Generable` (its emitted accessor aborts
                // at dyld load on some OS builds). The labeled reply is parsed into loose
                // fields, then the existing resolve/ground pipeline vets each value - so a
                // stray or malformed field is simply rejected rather than over-constraining.
                let reply = try await session.respond(to: trimmed).content
                let query = OnDeviceModelParsing.keyedFields(reply)
                let range = groundDateRange(resolveDateRange(query["daterange"] ?? ""), query: trimmed)
                let language = groundLanguage(resolveLanguage(query["language"] ?? "", in: languages), query: trimmed)
                let owner = groundOwner(resolveOwner(query["owner"] ?? "", in: owners), query: trimmed, owners: owners)
                let team = groundTeam(resolveTeam(query["team"] ?? "", in: teams), query: trimmed)
                let ownerName = owners.first { $0.email == owner }?.name ?? ""
                let text = groundText(query["text"] ?? "", languages: languages, ownerName: ownerName, team: team ?? "")
                let search = NamedSearch(
                    name: "",
                    search: text.trimmingCharacters(in: .whitespacesAndNewlines),
                    stateFilter: groundState(resolveState(query["state"] ?? ""), query: trimmed),
                    languageFilter: language,
                    ownerFilter: owner,
                    teamFilter: team,
                    typeFilter: groundType(resolveType(query["type"] ?? ""), query: trimmed),
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
            every other field out — do not guess or fill a field the request doesn't mention. Most \
            requests name just one or two fields. Languages available: \(optionList(languages, limit: 60)). \
            Owners available: \(optionList(owners.map(\.name), limit: 40)).

            Reply with only these lines, one field per line, and omit any field the request does \
            not name (or write its value as nil):
            text: real title keywords only, never the whole request, and never a language/person/type/draft status
            language: a language from the list
            owner: a person's name from the list
            type: live or take-home
            draft: draft or published
            """
            let session = LanguageModelSession(instructions: instructions)
            do {
                // Plain-text `respond(to:)`, never `@Generable`; see `generatePads`.
                let reply = try await session.respond(to: trimmed).content
                let query = OnDeviceModelParsing.keyedFields(reply)
                let language = groundLanguage(resolveLanguage(query["language"] ?? "", in: languages), query: trimmed)
                let owner = groundOwner(resolveOwner(query["owner"] ?? "", in: owners), query: trimmed, owners: owners)
                let ownerName = owners.first { $0.email == owner }?.name ?? ""
                let text = groundText(query["text"] ?? "", languages: languages, ownerName: ownerName, team: "")
                let search = NamedSearch(
                    name: "",
                    search: text.trimmingCharacters(in: .whitespacesAndNewlines),
                    languageFilter: language,
                    ownerFilter: owner,
                    typeFilter: groundType(resolveType(query["type"] ?? ""), query: trimmed),
                    draftFilter: groundDraft(resolveDraft(query["draft"] ?? ""), query: trimmed)
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
