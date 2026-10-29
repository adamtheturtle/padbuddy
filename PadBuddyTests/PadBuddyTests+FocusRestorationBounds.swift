import Foundation
@testable import PadBuddy
import Testing

@Suite("Persisted Focus stack bounds")
struct FocusRestorationBoundsTests {
    @Test func `decode and adoption retain only the newest bounded scopes`() throws {
        let scopes = (0 ..< 20).map { _ in FocusScopeStack.Scope(token: UUID(), accountID: UUID()) }
        let stored = FocusScopeStack(sessionID: "old", baseShowAll: true, baseAccountID: "", scopes: scopes)
        let data = try JSONEncoder().encode(stored)
        guard case let .stale(restored) = FocusScopeStackRestoration.decode(data, expectedSessionID: "new") else {
            Issue.record("Expected bounded stale stack")
            return
        }

        #expect(restored.scopes == Array(scopes.suffix(FocusScopeStack.maximumScopes)))
        #expect(FocusScopeStackRestoration.adopt(stored, sessionID: "new").scopes == restored.scopes)
    }

    @Test func `oversized data is rejected before decoding`() {
        let result = FocusScopeStackRestoration.decode(
            Data(repeating: 0, count: FocusScopeStackRestoration.maximumPersistedBytes + 1),
            expectedSessionID: "new",
            using: { _ in
                Issue.record("Oversized input must not be decoded")
                return FocusScopeStack(sessionID: "old", baseShowAll: true, baseAccountID: "")
            }
        )
        guard case .failed = result else {
            Issue.record("Expected size-limit failure")
            return
        }
    }

    @Test func `invalid base account identifiers are rejected`() throws {
        let stored = FocusScopeStack(sessionID: "old", baseShowAll: true, baseAccountID: "not-an-account")
        let result = try FocusScopeStackRestoration.decode(JSONEncoder().encode(stored), expectedSessionID: "new")
        guard case .failed = result else {
            Issue.record("Expected invalid-identifier failure")
            return
        }
    }
}
