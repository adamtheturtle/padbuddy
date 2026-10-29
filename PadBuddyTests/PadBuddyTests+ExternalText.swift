@testable import PadBuddy
import Testing

@Suite("External single-line text")
struct ExternalTextTests {
    @Test func `search text strips format controls and normalizes whitespace`() {
        #expect(ExternalText.singleLine("  Alice\n\tInterview\u{202e} title  ", limit: 200) == "Alice Interview title")
        #expect(ExternalText.singleLine("\n\t\u{202e}", limit: 200).isEmpty)
        #expect(ExternalText.singleLine(String(repeating: "x", count: 1_000_000), limit: 200).count == 200)
    }
}
