import Foundation

struct ScreenAIConversationIdentity: Hashable {
    let clientIdentity: ClientTaskIdentity
    let testID: Int
    let questionID: UUID
}

@Observable
final class ScreenAIConversationModel {
    private(set) var conversations: [ScreenAIConversation]?
    private(set) var loading = false
    private(set) var error: String?
    private(set) var identity: ScreenAIConversationIdentity?
    private var generation = 0

    func load(client: ScreenClient, identity: ScreenAIConversationIdentity) async {
        generation += 1
        let claim = generation
        self.identity = identity
        conversations = nil
        error = nil
        loading = true
        defer {
            if claim == generation {
                loading = false
            }
        }
        guard identity.clientIdentity == client.taskIdentity else { return }

        do {
            try Task.checkCancellation()
            let response = try await client.aiAssistConversations(
                testID: identity.testID,
                questionID: identity.questionID
            )
            guard self.identity == identity, claim == generation, !Task.isCancelled else { return }

            conversations = response
        } catch is CancellationError {
            return
        } catch {
            guard self.identity == identity, claim == generation, !Task.isCancelled else { return }

            self.error = String(error.localizedDescription.prefix(1000))
        }
    }
}
