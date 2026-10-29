import Foundation
@testable import PadBuddy
import Testing

@Suite("Invitation candidate link policy")
struct InvitationLinkPolicyTests {
    @Test(arguments: [
        "javascript:alert(1)", "file:///tmp/report", "http://screen.coderpad.io/test",
        "/relative", "https://user:secret@screen.coderpad.io/test"
    ])
    func `unsafe server links are unavailable for display copy and open`(_ raw: String) {
        #expect(ScreenInviteSheet.candidateLink(raw) == nil)
    }

    @Test func `safe HTTPS links are normalized and retained`() {
        #expect(ScreenInviteSheet.candidateLink(" https://screen.coderpad.io/test \n")?.absoluteString
            == "https://screen.coderpad.io/test")
        #expect(ScreenInviteSheet.candidateLink(nil) == nil)
    }
}
