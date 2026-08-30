import Foundation
@testable import PadBuddy
import Testing

@Suite("Account client context errors")
struct AccountClientContextErrorTests {
    @Test func `creation errors name the affected resource`() {
        #expect(AccountClientContextError.accountChanged.errorDescription
            == "That account changed while creating the pad. Try again.")
        #expect(AccountClientContextError.questionAccountChanged.errorDescription
            == "That account changed while creating the question. Try again.")
    }
}
