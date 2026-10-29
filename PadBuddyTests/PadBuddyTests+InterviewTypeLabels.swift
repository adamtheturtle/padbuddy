@testable import PadBuddy
import Testing

@Suite("Interview type labels")
@MainActor
struct InterviewTypeLabelTests {
    @Test func `known types retain localized labels`() {
        #expect(padTypeLabel("live") == InterviewType.live.label)
        #expect(padTypeLabel("take-home") == InterviewType.takeHome.label)
    }

    @Test func `unknown type labels are bounded and control free`() {
        #expect(padTypeLabel("\n\u{202E}") == "Unknown")
        let label = padTypeLabel("future\n\u{202E}" + String(repeating: "x", count: 10000))
        #expect(label.unicodeScalars.count <= 40)
        #expect(!label.contains("\n"))
        #expect(!label.contains("\u{202E}"))
    }
}
