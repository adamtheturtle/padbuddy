import Foundation
@testable import PadBuddy
import SwiftUI
import Testing

@Suite("Screen AI Assist conversations")
struct ScreenAIConversationTests {
    @Test @MainActor
    func `ordered messages retain roles timestamps and unknown structured output`() async throws {
        let client = ScreenClient.mock(key: "screen-ai-native-" + UUID().uuidString)
        let questionID = try #require(UUID(uuidString: "4143ca74-2f0e-4151-90d6-e1428739450b"))
        let identity = ScreenAIConversationIdentity(
            clientIdentity: client.taskIdentity,
            testID: 5001,
            questionID: questionID
        )
        let model = ScreenAIConversationModel()
        await model.load(client: client, identity: identity)
        let conversations = try #require(model.conversations)
        #expect(conversations.map(\.id) == ["conversation-1", "conversation-2"])
        #expect(conversations[0].messages.map(\.id) == ["message-1", "message-2"])
        #expect(conversations[0].messages.map(\.role) == [.user, .assistant])
        #expect(conversations[0].messages[0].creationTime == "2026-10-01T12:00:00.123Z")
        #expect(conversations[0].messages[0].outputItems == [.object([
            "type": .string("text"), "text": .string("Can you explain this test?"),
            "future": .object(["flag": .bool(false)])
        ])])
        #expect(conversations[1].messages.isEmpty)
        #expect(model.error == nil)
        #expect(model.loading == false)
        for message in conversations[0].messages {
            #expect(ImageRenderer(content: ScreenAIMessageView(message: message).frame(width: 600)).cgImage != nil)
        }
        #expect(ImageRenderer(content: ScreenAIConversationContent(conversations: conversations).frame(width: 600))
            .cgImage != nil)
    }

    @Test @MainActor
    func `empty conversations unavailable sessions and missing project questions have distinct outcomes`(
    ) async throws {
        let client = ScreenClient.mock(key: "screen-ai-empty-" + UUID().uuidString)
        let questionID = try #require(UUID(uuidString: "4143ca74-2f0e-4151-90d6-e1428739450b"))
        let model = ScreenAIConversationModel()
        await model.load(
            client: client,
            identity: ScreenAIConversationIdentity(
                clientIdentity: client.taskIdentity,
                testID: 5002,
                questionID: questionID
            )
        )
        #expect(model.conversations?.isEmpty == true)
        #expect(model.error == nil)
        await model.load(
            client: client,
            identity: ScreenAIConversationIdentity(
                clientIdentity: client.taskIdentity,
                testID: 5003,
                questionID: questionID
            )
        )
        #expect(model.conversations == nil)
        #expect(model.error != nil)
        await model.load(
            client: client,
            identity: ScreenAIConversationIdentity(
                clientIdentity: client.taskIdentity,
                testID: 5001,
                questionID: UUID()
            )
        )
        #expect(model.conversations == nil)
        #expect(model.error != nil)
        #expect(ImageRenderer(content: ScreenAIConversationContent(conversations: []).frame(width: 600))
            .cgImage != nil)
    }

    @Test @MainActor
    func `account changes permission failures and cancelled loads cannot retain earlier conversations`(
    ) async throws {
        let client = ScreenClient.mock(key: "screen-ai-scope-" + UUID().uuidString)
        let denied = ScreenClient.mock(unauthorized: true)
        let questionID = try #require(UUID(uuidString: "4143ca74-2f0e-4151-90d6-e1428739450b"))
        let model = ScreenAIConversationModel()
        let identity = ScreenAIConversationIdentity(
            clientIdentity: client.taskIdentity,
            testID: 5001,
            questionID: questionID
        )
        await model.load(client: client, identity: identity)
        #expect(model.conversations?.count == 2)
        let wrong = ScreenAIConversationIdentity(
            clientIdentity: denied.taskIdentity,
            testID: 5001,
            questionID: questionID
        )
        await model.load(client: client, identity: wrong)
        #expect(model.conversations == nil)
        #expect(model.identity == wrong)
        await model.load(client: denied, identity: wrong)
        #expect(model.error != nil)
        #expect(model.conversations == nil)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await model.load(client: client, identity: identity)
        }
        await cancelled.value
        #expect(model.error == nil)
        #expect(model.conversations == nil)
        #expect(model.loading == false)
    }

    @Test @MainActor
    func `missing empty and structured message output render without coercing false zero or null`() throws {
        for body in [#"{"id":"m1","role":"USER"}"#,
                     #"{"id":"m2","role":"ASSISTANT","output_items":[]}"#,
                     #"{"id":"m3","role":"ASSISTANT","output_items":[false,0,null,{"future":[]}]}"#] {
            let message = try JSONDecoder().decode(ScreenAIMessage.self, from: Data(body.utf8))
            #expect(ImageRenderer(content: ScreenAIMessageView(message: message).frame(width: 600)).cgImage != nil)
            if message.id == "m1" {
                #expect(message.outputItems == nil)
            }
            if message.id == "m2" {
                #expect(message.outputItems?.isEmpty == true)
            }
            if message.id == "m3" {
                #expect(message.outputItems == [.bool(false), .number(0), .null, .object(["future": .array([])])])
                let original = try ScreenAIOriginalOutputView.originalJSON(message.outputItems ?? [])
                #expect(try JSONDecoder().decode(JSONValue.self, from: Data(original.utf8))
                    == .array(message.outputItems ?? []))
                let output = StructuredContentRows(.array(message.outputItems ?? []))
                #expect(output.rows.map(\.text) == ["No", "0", "Not provided", "", ""])
            }
        }
    }
}
