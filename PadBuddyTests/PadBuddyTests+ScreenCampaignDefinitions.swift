@testable import PadBuddy
import SwiftUI
import Testing

@MainActor
struct ScreenCampaignDefinitionTests {
    private func details(id: Int, name: String = "Backend") throws -> ScreenCampaignDetails {
        try JSONDecoder().decode(ScreenCampaignDetails.self, from: JSONSerialization.data(withJSONObject: [
            "id": id, "name": name,
            "questions": [
                ["type": "QUESTION", "question_id": "4143ca74-2f0e-4151-90d6-e1428739450b"],
                ["type": "RANDOM_QUESTION_SET", "configuration": ["domain": "backend", "skills": []]]
            ],
            "settings": ["languages": ["en"], "timer": ["mode": "GLOBAL", "duration_minutes": 60],
                         "copy_paste_blocked": false, "ai_assist_enabled": false, "enabled_coding_agents": ""]
        ]))
    }

    @Test
    func `demo campaign definition is available through the released SDK`() async {
        let model = ScreenCampaignDefinitionModel()
        let client = ScreenClient.mock(key: "definition-demo-\(UUID().uuidString)")
        let identity = ScreenCampaignDefinitionIdentity(accountID: UUID(), clientIdentity: client.taskIdentity,
                                                        campaignID: 101)
        await model.load(client: client, identity: identity)
        #expect(model.details?.id == 101)
        #expect(model.details?.questions.isEmpty == false)
        #expect(model.details?.settings?.aiAssistEnabled == false)
        #expect(model.error == nil)
    }

    @Test
    func `superseded campaign responses cannot replace the current selection`() async throws {
        let model = ScreenCampaignDefinitionModel()
        let client = ScreenClient.mock()
        let account = UUID()
        let first = ScreenCampaignDefinitionIdentity(accountID: account, clientIdentity: client.taskIdentity,
                                                     campaignID: 1)
        let second = ScreenCampaignDefinitionIdentity(accountID: UUID(), clientIdentity: client.taskIdentity,
                                                      campaignID: 2)
        let previous = try details(id: 1)
        let current = try details(id: 2, name: "Current")
        var continuation: CheckedContinuation<ScreenCampaignDetails, Never>?
        let pending = Task {
            await model.load(client: client, identity: first) { _ in
                await withCheckedContinuation { continuation = $0 }
            }
        }
        while continuation == nil {
            await Task.yield()
        }
        await model.load(client: client, identity: second) { _ in current }
        continuation?.resume(returning: previous)
        await pending.value
        #expect(model.details == current)
        #expect(model.identity == second)
        #expect(!model.loading)
    }

    @Test
    func `wrong campaign identities fail without publishing details and can be retried`() async throws {
        let model = ScreenCampaignDefinitionModel()
        let client = ScreenClient.mock()
        let identity = ScreenCampaignDefinitionIdentity(accountID: UUID(), clientIdentity: client.taskIdentity,
                                                        campaignID: 1)
        let wrong = try details(id: 2)
        await model.load(client: client, identity: identity) { _ in wrong }
        #expect(model.details == nil)
        #expect(model.error != nil)
        let correct = try details(id: 1)
        await model.load(client: client, identity: identity) { _ in correct }
        #expect(model.details == correct)
        #expect(model.error == nil)
    }

    @Test
    func `campaign settings and ordered questions render in compact Spanish`() throws {
        let value = try details(id: 1)
        let content = ScreenCampaignDefinitionContent(details: value, client: .mock(), accountID: UUID())
        let renderer = ImageRenderer(content: content.frame(width: 340, height: 600)
            .environment(\.locale, Locale(identifier: "es")))
        #expect((renderer.nsImage?.size.height ?? 0) > 0)
    }
}
