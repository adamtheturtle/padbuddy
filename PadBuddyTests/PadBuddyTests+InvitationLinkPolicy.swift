import Foundation
@testable import PadBuddy
import Testing

@Suite("Invitation candidate link policy")
struct InvitationLinkPolicyTests {
    @Test(arguments: [
        "javascript:alert(1)", "file:///tmp/report", "http://candidate.example.com/test",
        "/relative", "https://user:secret@candidate.example.com/test"
    ])
    func `unsafe server links are unavailable for display copy and open`(_ raw: String) {
        #expect(ScreenInviteSheet.candidateLink(raw) == nil)
    }

    @Test func `safe HTTPS links are normalized and retained`() {
        #expect(ScreenInviteSheet.candidateLink(" https://candidate.example.com/test \n")?.absoluteString
            == "https://candidate.example.com/test")
        #expect(ScreenInviteSheet.candidateLink(nil) == nil)
    }
}
