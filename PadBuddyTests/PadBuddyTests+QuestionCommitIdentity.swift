@testable import PadBuddy
import Testing

@Suite("Question commit identity")
@MainActor
struct QuestionCommitIdentityTests {
    @Test func `stored question commits require current account credentials`() {
        let current = Account(name: "Current", apiKey: "new")
        let retired = Account(name: "Current", apiKey: "old", id: current.id)

        #expect(QuestionCommitIdentity.isCurrent(
            accountID: current.id,
            clientIdentity: current.makeClient().taskIdentity,
            accounts: [current]
        ))
        #expect(!QuestionCommitIdentity.isCurrent(
            accountID: current.id,
            clientIdentity: retired.makeClient().taskIdentity,
            accounts: [current]
        ))
        #expect(!QuestionCommitIdentity.isCurrent(
            accountID: current.id,
            clientIdentity: retired.makeClient().taskIdentity,
            accounts: []
        ))
    }

    @Test func `standalone test clients remain usable without a stored account`() {
        let identity = Account(name: "Fixture", apiKey: "fixture").makeClient().taskIdentity

        #expect(QuestionCommitIdentity.isCurrent(
            accountID: nil, clientIdentity: identity, accounts: []
        ))
    }
}
