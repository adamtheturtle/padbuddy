import Foundation
@testable import PadBuddy
import SwiftUI
import Testing

@Suite("Native Screen campaign creation")
struct ScreenCampaignCreationTests {
    @Test
    func `untouched settings are omitted and fixed and random question order is retained`() throws {
        let questionID = UUID()
        var draft = ScreenCampaignDraft(name: " Campaign ")
        draft.questions = [ScreenCampaignQuestionDraft(questionID: questionID),
                           ScreenCampaignQuestionDraft(random: ScreenRandomQuestionDraft())]
        #expect(draft.validationMessage == nil)
        let data = try JSONEncoder().encode(draft.request)
        let fields = try JSONDecoder().decode([String: JSONValue].self, from: data)
        #expect(fields == ["name": .string("Campaign"), "questions": .array([
            .object(["type": .string("QUESTION"), "question_id": .string(questionID.uuidString)]),
            .object(["type": .string("RANDOM_QUESTION_SET"), "configuration": .object([:])])
        ])])
        #expect(draft.settings.request == nil)
        #expect(draft.request.teamID == nil)
    }

    @Test
    func `explicit false disabled agents timer and access settings survive encoding`() throws {
        var settings = ScreenCampaignSettingsDraft()
        settings.aiEnabled = false
        settings.copyPasteBlocked = false
        settings.fullScreen = false
        settings.simplifiedReport = false
        settings.followUpEnabled = false
        settings.webcamEnabled = false
        settings.webcamAI = false
        settings.codingAgent = ""
        settings.timerMode = .global
        settings.timerDuration = " 60 "
        settings.expirationDays = " 14 "
        settings.overrideAccess = true
        settings.accessStart = Date(timeIntervalSince1970: 1_800_000_000)
        settings.accessEnd = settings.accessStart.addingTimeInterval(3600)
        settings.overrideLanguages = true
        settings.languages = "en, es"
        #expect(settings.validationMessage == nil)
        let request = try #require(settings.request)
        let data = try JSONEncoder().encode(request)
        let fields = try JSONDecoder().decode([String: JSONValue].self, from: data)
        #expect(fields["ai_assist_enabled"] == .bool(false))
        #expect(fields["copy_paste_blocked"] == .bool(false))
        #expect(fields["full_screen_required"] == .bool(false))
        #expect(fields["send_candidate_simplified_report"] == .bool(false))
        #expect(fields["enabled_coding_agents"] == .string(""))
        #expect(fields["timer"] == .object(["mode": .string("GLOBAL"), "duration_minutes": .number(60)]))
        #expect(fields["follow_up_questions"] == .object(["enabled": .bool(false)]))
        #expect(fields["webcam_proctoring"] == .object(["enabled": .bool(false), "ai_analysis_enabled": .bool(false)]))
        #expect(request.invitationExpirationDays == 14)
        #expect(request.languages == ["en", "es"])
        #expect(request.accessPeriod?.minStartTime == settings.accessStart.ISO8601Format())
    }

    @Test
    func `invalid names selections identities timing and dependent options prevent submission`() {
        var draft = ScreenCampaignDraft()
        #expect(draft.validationMessage != nil)
        draft.name = "Campaign"
        #expect(draft.validationMessage != nil)
        draft.questions = [ScreenCampaignQuestionDraft()]
        #expect(draft.validationMessage != nil)
        let id = UUID()
        draft.questions[0].questionID = id
        #expect(draft.validationMessage == nil)
        draft.questions.append(ScreenCampaignQuestionDraft(questionID: id))
        #expect(draft.validationMessage != nil)
        draft.questions.removeLast()
        draft.teamID = "invalid"
        #expect(draft.validationMessage != nil)
        draft.teamID = " \(UUID().uuidString) "
        #expect(draft.validationMessage == nil)
        var settings = ScreenCampaignSettingsDraft()
        settings.timerMode = .global
        #expect(settings.validationMessage != nil)
        settings.timerDuration = "60"
        #expect(settings.validationMessage == nil)
        settings.timerMode = .unlimited
        #expect(settings.validationMessage != nil)
        settings.timerDuration = ""
        settings.followUpEnabled = false
        settings.followUpFormat = .text
        #expect(settings.validationMessage != nil)
        settings.followUpFormat = nil
        settings.webcamEnabled = false
        settings.webcamAI = true
        #expect(settings.validationMessage != nil)
        settings.webcamAI = false
        settings.overrideAccess = true
        settings.accessEnd = settings.accessStart.addingTimeInterval(-1)
        #expect(settings.validationMessage != nil)
    }

    @Test
    func `random selection parses IDs and sends only the chosen inclusion policy`() {
        let first = UUID(), second = UUID()
        var random = ScreenRandomQuestionDraft()
        random.ids = "\(first.uuidString),\n \(second.uuidString)"
        random.skills = "Algorithms, Data structures"
        random.duration = " 30 "
        #expect(random.validationMessage == nil)
        #expect(random.request.includedQuestionIDs == [first, second])
        #expect(random.request.excludedQuestionIDs == nil)
        #expect(random.request.targetDurationMinutes == 30)
        random.include = false
        #expect(random.request.includedQuestionIDs == nil)
        #expect(random.request.excludedQuestionIDs == [first, second])
        random.ids += ", invalid"
        #expect(random.validationMessage != nil)
    }

    @Test @MainActor
    func `successful creation is account scoped and cannot run again`() async throws {
        let client = ScreenClient.mock(key: "campaign-create-" + UUID().uuidString)
        let other = ScreenClient.mock(key: "campaign-other-" + UUID().uuidString)
        let before = try await client.listCampaigns()
        let others = try await other.listCampaigns()
        let model = ScreenCampaignCreationModel()
        let draft = validDraft()
        let created = await model.create(draft, client: client, isCurrent: { true })
        let id = try #require(created)
        #expect(model.createdID == id)
        #expect(model.error == nil)
        let current = try await client.listCampaigns()
        #expect(current.map(\.id) == before.map(\.id) + [id])
        #expect(current.last?.name == draft.name)
        let repeated = await model.create(draft, client: client, isCurrent: { true })
        #expect(repeated == nil)
        let unchanged = try await other.listCampaigns()
        #expect(unchanged == others)
    }

    @Test @MainActor
    func `account changes after creation retain success and prevent a duplicate retry`() async throws {
        let client = ScreenClient.mock(key: "campaign-context-" + UUID().uuidString)
        let before = try await client.listCampaigns()
        let model = ScreenCampaignCreationModel()
        var checks = 0
        let result = await model.create(validDraft(), client: client, isCurrent: {
            checks += 1
            return checks == 1
        })
        #expect(result == nil)
        #expect(model.createdID != nil)
        #expect(model.contextChangedAfterCreation == true)
        #expect(model.error == nil)
        let repeated = await model.create(validDraft(), client: client, isCurrent: { true })
        #expect(repeated == nil)
        let current = try await client.listCampaigns()
        #expect(current.count == before.count + 1)
    }

    @Test @MainActor
    func `permission errors retired accounts and cancellation retain unsaved input`() async {
        let draft = validDraft()
        let model = ScreenCampaignCreationModel()
        let unauthorized = await model.create(draft, client: .mock(unauthorized: true), isCurrent: { true })
        #expect(unauthorized == nil)
        #expect(model.error != nil)
        #expect(model.createdID == nil)
        let retired = await model.create(draft, client: .mock(), isCurrent: { false })
        #expect(retired == nil)
        #expect(model.error != nil)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await model.create(draft, client: .mock(), isCurrent: { true })
        }
        let cancelled = await task.value
        #expect(cancelled == nil)
        #expect(model.error == nil)
        #expect(draft.name == "Native Campaign")
    }

    @Test @MainActor
    func `oversized campaign bodies fail locally without creating a campaign`() async throws {
        let client = ScreenClient.mock(key: "campaign-bounds-" + UUID().uuidString)
        let before = try await client.listCampaigns()
        let model = ScreenCampaignCreationModel()
        var random = ScreenRandomQuestionDraft()
        random.domain = String(repeating: "x", count: 1024 * 1024)
        let draft = ScreenCampaignDraft(name: "Bounded Campaign",
                                        questions: [ScreenCampaignQuestionDraft(random: random)])
        let created = await model.create(draft, client: client, isCurrent: { true })
        #expect(created == nil)
        #expect(model.error != nil)
        #expect(model.createdID == nil)
        let after = try await client.listCampaigns()
        #expect(after == before)
    }

    @Test @MainActor
    func `creation form renders with explicit team defaults and question choices`() {
        let renderer = ImageRenderer(content: ScreenCampaignCreationSheet(client: .mock(), accountID: UUID(),
                                                                          onCreated: { _ in })
                .frame(width: 650, height: 750))
        #expect(renderer.cgImage != nil)
    }

    private func validDraft() -> ScreenCampaignDraft {
        ScreenCampaignDraft(name: "Native Campaign", questions: [ScreenCampaignQuestionDraft(questionID: UUID())])
    }
}
