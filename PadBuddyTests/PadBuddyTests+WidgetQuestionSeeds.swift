import Foundation
@testable import PadBuddy
import Testing

@Suite("Widget question seed validation")
struct WidgetQuestionSeedTests {
    @Test(arguments: [0, -1]) func `explicit invalid question seeds never become blank creates`(_ id: Int) {
        #expect(WidgetSharedStore.validatedNewPadRequest(account: UUID().uuidString, question: id) == nil)
    }

    @Test func `a question seed requires an account and preserves its request identity`() throws {
        #expect(WidgetSharedStore.validatedNewPadRequest(account: nil, question: 42) == nil)
        let owner = UUID().uuidString, requestID = UUID()
        let request = try #require(WidgetSharedStore.validatedNewPadRequest(
            account: owner, question: 42, requestID: requestID
        ))
        #expect(request.account == owner)
        #expect(request.question == 42)
        #expect(request.id == requestID)
        let blank = try #require(WidgetSharedStore.validatedNewPadRequest(account: nil, question: nil))
        #expect(blank.account == nil)
        #expect(blank.question == nil)
    }
}
