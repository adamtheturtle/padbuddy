@testable import PadBuddy
import Testing

@Suite("Playback system authors")
struct PlaybackSystemAuthorTests {
    @Test(arguments: ["CoderPad", "coderpad", "CODERPAD", "  cOdErPaD  "])
    func `seed author casing never creates a participant`(_ author: String) {
        #expect(!PadPlaybackAuthors.isParticipant(author))
    }

    @Test func `a real participant remains visible`() {
        #expect(PadPlaybackAuthors.isParticipant("Ada"))
    }
}
