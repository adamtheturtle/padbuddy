import Foundation
@testable import PadBuddy
import Testing

@Suite("Command title edit request")
struct CommandTitleEditRequestTests {
    private let accountID = UUID()

    @Test
    func `request requires the same account item and source title`() {
        let scope = CommandTitleEditScope(accountID: accountID, itemID: "pad-1", title: "Original")
        let request = CommandTitleEditRequest(scope: scope)

        #expect(request.matches(scope, editingAllowed: true))
        #expect(!request.matches(.init(accountID: UUID(), itemID: "pad-1", title: "Original"),
                                 editingAllowed: true))
        #expect(!request.matches(.init(accountID: accountID, itemID: "pad-2", title: "Original"),
                                 editingAllowed: true))
        #expect(!request.matches(.init(accountID: accountID, itemID: "pad-1", title: "Changed"),
                                 editingAllowed: true))
    }

    @Test
    func `request cannot open a read only editor`() {
        let scope = CommandTitleEditScope(accountID: accountID, itemID: "pad-1", title: "Original")

        #expect(!CommandTitleEditRequest(scope: scope).matches(scope, editingAllowed: false))
    }
}
