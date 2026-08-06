@testable import PadBuddy
import Testing

@Suite("Command title edit focus")
struct CommandTitleEditFocusTests {
    @Test
    func `focus movement never commits a title`() {
        #expect(!CommandTitleEditFocusPolicy.shouldCommit(focused: false))
        #expect(!CommandTitleEditFocusPolicy.shouldCommit(focused: true))
    }
}
