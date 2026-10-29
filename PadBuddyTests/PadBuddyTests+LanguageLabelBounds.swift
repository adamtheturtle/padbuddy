@testable import PadBuddy
import Testing

@Suite("Remote language labels")
struct LanguageLabelBoundsTests {
    @Test func `unknown language labels remove controls and fit a single bounded line`() {
        #expect("\u{202E}\n".coderPadLanguageDisplayName == "Unknown")
        let display = ("custom\n\u{202E}" + String(repeating: "x", count: 100)).coderPadLanguageDisplayName
        #expect(display.unicodeScalars.count <= 64)
        #expect(!display.contains("\n"))
        #expect(!display.contains("\u{202E}"))
    }
}
