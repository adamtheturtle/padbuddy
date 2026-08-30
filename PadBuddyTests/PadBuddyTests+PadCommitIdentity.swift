@testable import PadBuddy
import Testing

@Suite("Pad commit identity")
@MainActor
struct PadCommitIdentityTests {
    @Test func `stored pad commits require current account credentials`() {
        let current = Account(name: "Current", apiKey: "new")
        let retired = Account(name: "Current", apiKey: "old", id: current.id)

        #expect(PadCommitIdentity.isCurrent(
            accountID: current.id,
            clientIdentity: current.makeClient().taskIdentity,
            accounts: [current]
        ))
        #expect(!PadCommitIdentity.isCurrent(
            accountID: current.id,
            clientIdentity: retired.makeClient().taskIdentity,
            accounts: [current]
        ))
        #expect(!PadCommitIdentity.isCurrent(
            accountID: current.id,
            clientIdentity: retired.makeClient().taskIdentity,
            accounts: []
        ))
    }

    @Test func `standalone pad fixtures remain usable without a stored account`() {
        let identity = Account(name: "Fixture", apiKey: "fixture").makeClient().taskIdentity

        #expect(PadCommitIdentity.isCurrent(
            accountID: nil, clientIdentity: identity, accounts: []
        ))
    }
}
