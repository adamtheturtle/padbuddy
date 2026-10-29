@testable import PadBuddy
import Testing

@Suite("Screen tag presentation")
struct ScreenTagPresentationTests {
    @Test func `tags are bounded before joining with an omission indicator`() {
        let tags = Array(repeating: String(repeating: "x", count: 10000), count: 10000)
        let presentation = ScreenTagPresentation(tags)
        #expect(presentation.text.unicodeScalars.count <= 16 * 80 + 15 * 2)
        #expect(presentation.omitted)
    }

    @Test func `ordinary tags retain order and unsafe scalars cannot inject rows`() {
        let presentation = ScreenTagPresentation(["Swift", "iOS\n\u{202E} Interview"])
        #expect(presentation.text == "Swift, iOS Interview")
        #expect(!presentation.omitted)
        #expect(ScreenTagPresentation([]).text.isEmpty)
        #expect(!ScreenTagPresentation([]).omitted)
        #expect(ScreenTagPresentation([" \n"]).omitted)
    }
}
