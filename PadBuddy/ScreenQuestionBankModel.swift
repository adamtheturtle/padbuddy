import Foundation

struct ScreenBankIdentity: Hashable {
    let accountID: UUID
    let clientIdentity: ClientTaskIdentity
}

@Observable
final class ScreenQuestionBankModel {
    private(set) var questions: [ScreenQuestionSummary] = []
    private(set) var nextStart: Int?
    private(set) var loading = false
    private(set) var error: String?
    private(set) var identity: ScreenBankIdentity?
    private(set) var filters = ScreenQuestionFilters()
    private var generation = 0

    func reload(client: ScreenClient, identity: ScreenBankIdentity, filters: ScreenQuestionFilters) async {
        guard identity.clientIdentity == client.taskIdentity else { return }

        generation += 1
        self.identity = identity
        self.filters = filters
        questions = []
        nextStart = nil
        await fetch(client: client, start: 0, claim: generation, identity: identity)
    }

    func loadMore(client: ScreenClient, identity: ScreenBankIdentity) async {
        guard !loading, self.identity == identity,
              identity.clientIdentity == client.taskIdentity, let nextStart else { return }

        await fetch(client: client, start: nextStart, claim: generation, identity: identity)
    }

    private func fetch(client: ScreenClient, start: Int, claim: Int, identity: ScreenBankIdentity) async {
        loading = true
        error = nil
        defer {
            if claim == generation {
                loading = false
            }
        }
        do {
            let page = try await client.listQuestions(filters: filters, start: start, limit: 50)
            guard claim == generation, self.identity == identity, !Task.isCancelled else { return }

            if page.pagination?.hasMoreItems == true {
                guard let next = page.pagination?.nextStart, next > start else {
                    throw CoderPadError
                        .decode(String(localized: "The question list returned an invalid next page."))
                }

                nextStart = next
            } else {
                nextStart = nil
            }
            guard questions.count + page.questions.count <= 10000 else {
                throw CoderPadError
                    .decode(String(localized: "Refine the filters to browse more than 10000 questions."))
            }

            var seen = Set(questions.map(\.id))
            questions.append(contentsOf: page.questions.filter { seen.insert($0.id).inserted })
        } catch is CancellationError {
            return
        } catch {
            guard claim == generation, self.identity == identity, !Task.isCancelled else { return }

            self.error = error.localizedDescription
        }
    }
}

struct ScreenBankDetailIdentity: Hashable {
    let bank: ScreenBankIdentity
    let questionID: UUID
    let language: String?
}

@Observable
final class ScreenBankDetailModel {
    private(set) var question: ScreenQuestionDetails?
    private(set) var insights: ScreenQuestionInsights?
    private(set) var error: String?
    private(set) var insightsError: String?
    private(set) var loading = false
    private(set) var identity: ScreenBankDetailIdentity?
    private var generation = 0

    func load(client: ScreenClient, identity: ScreenBankDetailIdentity) async {
        guard identity.bank.clientIdentity == client.taskIdentity else { return }

        generation += 1
        let claim = generation
        self.identity = identity
        question = nil
        insights = nil
        error = nil
        insightsError = nil
        loading = true
        defer {
            if claim == generation {
                loading = false
            }
        }
        do {
            let question = try await client.getQuestion(id: identity.questionID)
            guard isCurrent(identity, claim: claim) else { return }
            guard question.id == identity.questionID else {
                throw CoderPadError.decode(String(localized: "The service returned a different question."))
            }

            self.question = question
        } catch is CancellationError {
            return
        } catch {
            guard isCurrent(identity, claim: claim) else { return }

            self.error = error.localizedDescription
            return
        }
        await loadInsights(client: client, identity: identity, claim: claim)
    }

    private func loadInsights(client: ScreenClient, identity: ScreenBankDetailIdentity, claim: Int) async {
        do {
            let insights = try await client.questionInsights(
                id: identity.questionID,
                programmingLanguage: identity.language
            )
            guard isCurrent(identity, claim: claim) else { return }

            self.insights = insights
        } catch is CancellationError {
            return
        } catch {
            guard isCurrent(identity, claim: claim) else { return }

            insightsError = error.localizedDescription
        }
    }

    private func isCurrent(_ identity: ScreenBankDetailIdentity, claim: Int) -> Bool {
        self.identity == identity && claim == generation && !Task.isCancelled
    }
}

struct ScreenBankFilterDraft {
    var type = ""
    var minimumDuration = ""
    var maximumDuration = ""
    var difficulty: ScreenQuestionFilters.Difficulty?
    var domain = ""
    var skill = ""
    var language = ""
    var bankOrigin: Bool?
    var product: ScreenQuestionFilters.Product?
    var sort: ScreenQuestionFilters.Sort?
    var order: ScreenQuestionFilters.Order?

    var validationMessage: String? {
        for value in [minimumDuration, maximumDuration] where !trimmed(value).isEmpty {
            guard let duration = Int(trimmed(value)), (0 ... Int(Int32.max)).contains(duration) else {
                return String(localized: "Durations must be whole seconds from 0 to 2147483647.")
            }
        }
        if let minimum = Int(trimmed(minimumDuration)), let maximum = Int(trimmed(maximumDuration)),
           minimum > maximum {
            return String(localized: "Minimum duration must not exceed maximum duration.")
        }
        return nil
    }

    var filters: ScreenQuestionFilters {
        ScreenQuestionFilters(
            type: optional(type),
            durationSecondsMin: Int(trimmed(minimumDuration)),
            durationSecondsMax: Int(trimmed(maximumDuration)),
            difficulty: difficulty,
            domain: optional(domain),
            skill: optional(skill),
            programmingLanguage: optional(language),
            fromCoderPadQuestionBank: bankOrigin,
            product: product,
            sort: sort,
            order: order
        )
    }

    private func optional(_ value: String) -> String? {
        trimmed(value).isEmpty ? nil : trimmed(value)
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
