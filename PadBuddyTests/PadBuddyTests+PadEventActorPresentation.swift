@testable import PadBuddy
import Testing

@Suite("Pad event actor presentation")
struct PadEventActorPresentationTests {
    @Test func `actor names are bounded safe single line labels`() {
        let event = PadEvent(message: "", kind: "typed", metadata: nil,
                             userName: "Ada\n\u{202E}" + String(repeating: "x", count: 10000),
                             userEmail: nil, createdAt: nil)
        let actor = PadEventPresentationCache.actor(event)
        #expect(actor?.unicodeScalars.count ?? 0 <= 120)
        #expect(actor?.hasPrefix("Ada ") == true)
        #expect(actor?.contains("\u{202E}") == false)
        #expect(actor?.contains("\n") == false)
    }

    @Test func `blank unsafe names fall back to a bounded email`() {
        let event = PadEvent(message: "", kind: "typed", metadata: nil,
                             userName: " \n\u{202E}", userEmail: "ada@example.com", createdAt: nil)
        #expect(PadEventPresentationCache.actor(event) == "ada@example.com")
        let empty = PadEvent(message: "", kind: "typed", metadata: nil,
                             userName: " ", userEmail: "\n", createdAt: nil)
        #expect(PadEventPresentationCache.actor(empty) == nil)
    }
}
