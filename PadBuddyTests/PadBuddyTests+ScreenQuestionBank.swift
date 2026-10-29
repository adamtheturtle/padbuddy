import Foundation
@testable import PadBuddy
import SwiftUI
import Testing

@Suite("Screen question bank")
struct ScreenQuestionBankTests {
    @Test
    func `every filter preserves false zero and sort values while duration input validates`() {
        var draft = ScreenBankFilterDraft()
        draft.type = " CODE "
        draft.minimumDuration = "0"
        draft.maximumDuration = "120"
        draft.difficulty = .easy
        draft.domain = "Backend"
        draft.skill = "Problem solving"
        draft.language = "C++"
        draft.bankOrigin = false
        draft.product = .screen
        draft.sort = .durationSeconds
        draft.order = .desc
        #expect(draft.filters == ScreenQuestionFilters(type: "CODE", durationSecondsMin: 0,
                                                       durationSecondsMax: 120, difficulty: .easy, domain: "Backend",
                                                       skill: "Problem solving", programmingLanguage: "C++",
                                                       fromCoderPadQuestionBank: false, product: .screen,
                                                       sort: .durationSeconds, order: .desc))
        #expect(draft.validationMessage == nil)
        draft.minimumDuration = "121"
        #expect(draft.validationMessage != nil)
        for value in ["-1", "1.5", "2147483648", "seconds"] {
            draft.minimumDuration = value
            #expect(draft.validationMessage != nil)
        }
        #expect(ScreenBankText.localized(["es": "Nombre", "en": "Name"], locale: "es") == "Nombre")
        #expect(ScreenBankText.localized(["fr": "Titre"], locale: "de") == "Titre")
    }

    @Test @MainActor
    func `paged browsing retains filters and UUID order across pages and account changes`() async throws {
        let client = ScreenClient.mock(key: "bank-pages-" + UUID().uuidString)
        for index in 0 ..< 55 {
            _ = try await client.createQuestion(ScreenQuestionSave(type: .text, domain: "Paging",
                                                                   durationSeconds: 0, difficulty: .easy,
                                                                   title: ["en": String(format: "%03d", index)],
                                                                   locales: ["en"], textDetails: ScreenTextInput()))
        }
        let identity = ScreenBankIdentity(accountID: UUID(), clientIdentity: client.taskIdentity)
        let filters = ScreenQuestionFilters(type: "TEXT", durationSecondsMin: 0, durationSecondsMax: 0,
                                            difficulty: .easy, domain: "Paging", fromCoderPadQuestionBank: false,
                                            sort: .title, order: .asc)
        let model = ScreenQuestionBankModel()
        await model.reload(client: client, identity: identity, filters: filters)
        #expect(model.questions.count == 50)
        #expect(model.nextStart == 50)
        await model.loadMore(client: client, identity: identity)
        #expect(model.questions.compactMap { $0.title?["en"] } == (0 ..< 55).map { String(format: "%03d", $0) })
        #expect(Set(model.questions.map(\.id)).count == 55)
        #expect(model.filters == filters)
        #expect(model.nextStart == nil)
        #expect(model.error == nil)
        let other = ScreenClient.mock(key: "bank-other-" + UUID().uuidString)
        let second = ScreenBankIdentity(accountID: UUID(), clientIdentity: other.taskIdentity)
        await model.reload(client: other, identity: second, filters: filters)
        #expect(model.questions.isEmpty)
        #expect(model.identity == second)
        #expect(model.loading == false)
    }

    @Test @MainActor
    func `list permission errors and cancelled loads retain no prior account rows`() async {
        let client = ScreenClient.mock(unauthorized: true)
        let model = ScreenQuestionBankModel()
        let identity = ScreenBankIdentity(accountID: UUID(), clientIdentity: client.taskIdentity)
        await model.reload(client: client, identity: identity, filters: ScreenQuestionFilters())
        #expect(model.error != nil)
        #expect(model.questions.isEmpty)
        let valid = ScreenClient.mock(key: "bank-cancel-" + UUID().uuidString)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await model.reload(client: valid,
                               identity: ScreenBankIdentity(accountID: UUID(), clientIdentity: valid.taskIdentity),
                               filters: ScreenQuestionFilters())
        }
        await task.value
        #expect(model.questions.isEmpty)
        #expect(model.error == nil)
    }

    @Test @MainActor
    func `question and insights retain zero false language scope and independent errors`() async throws {
        let client = ScreenClient.mock(key: "bank-detail-" + UUID().uuidString)
        let questionID = try #require(UUID(uuidString: "4143ca74-2f0e-4151-90d6-e1428739450b"))
        let bank = ScreenBankIdentity(accountID: UUID(), clientIdentity: client.taskIdentity)
        let model = ScreenBankDetailModel()
        await model.load(client: client, identity: ScreenBankDetailIdentity(bank: bank,
                                                                            questionID: questionID, language: "C++"))
        #expect(model.question?.id == questionID)
        #expect(model.question?.projectDetails?.aiAssistAllowed == false)
        #expect(model.question?.evaluation?.testReport?.testCases?.first?.points == 0)
        #expect(model.insights?.usage?.averageScore == 0.5)
        #expect(model.insights?.frequentAnswers?.first?.correct == false)
        let answerCount = model.insights?.frequentAnswers?.first?.count
        #expect(answerCount == 0)
        await model.load(client: client, identity: ScreenBankDetailIdentity(bank: bank,
                                                                            questionID: questionID,
                                                                            language: "invalid"))
        #expect(model.question?.id == questionID)
        #expect(model.error == nil)
        #expect(model.insights == nil)
        #expect(model.insightsError != nil)
        let missing = UUID()
        await model.load(client: client, identity: ScreenBankDetailIdentity(bank: bank,
                                                                            questionID: missing, language: nil))
        #expect(model.question == nil)
        #expect(model.insights == nil)
        #expect(model.error != nil)
    }

    @Test @MainActor
    func `bank question content and insights render for every provided type`() async throws {
        let client = ScreenClient.mock(key: "bank-render-" + UUID().uuidString)
        for summary in try await client.listAllQuestions() {
            let question = try await client.getQuestion(id: summary.id)
            let renderer = ImageRenderer(content: ScreenBankQuestionContent(question: question, locale: "en")
                .frame(width: 600))
            #expect(renderer.cgImage != nil)
        }
        let id = try #require(UUID(uuidString: "4143ca74-2f0e-4151-90d6-e1428739450b"))
        let insights = try await client.questionInsights(id: id)
        let renderer = ImageRenderer(content: ScreenBankInsightsView(insights: insights).frame(width: 600))
        #expect(renderer.cgImage != nil)
    }
}
