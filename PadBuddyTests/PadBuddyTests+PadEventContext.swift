@testable import PadBuddy
import Testing

@Suite("Pad event context validation")
struct PadEventContextTests {
    @Test(arguments: ["0", "-1", "+1", "123\nEnded interview", "not an ID", "999999999999999999999999999"])
    func `added question context requires a positive representable numeric ID`(_ metadata: String) {
        #expect(PadEventPresentationCache.context(event(metadata)) == nil)
    }

    @Test func `valid question IDs are canonicalized and oversized metadata is rejected before trimming`() {
        #expect(PadEventPresentationCache.context(event(" 0042 ")) == "#42")
        #expect(PadEventPresentationCache.context(event(String(repeating: " ", count: 10000) + "42")) == nil)
    }

    private func event(_ metadata: String) -> PadEvent {
        PadEvent(message: "", kind: "added_question", metadata: metadata,
                 userName: nil, userEmail: nil, createdAt: nil)
    }
}
