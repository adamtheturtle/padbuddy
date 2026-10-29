@testable import PadBuddy
import Testing

@Suite("Question metadata presentation")
struct QuestionMetadataPresentationTests {
    @Test func `remote author and organization labels are bounded single line text`() {
        let label = QuestionMetadataPresentation.label("Remote\n\u{202E}" + String(repeating: "x", count: 10000))
        #expect(label?.unicodeScalars.count ?? 0 <= 200)
        #expect(label?.hasPrefix("Remote ") == true)
        #expect(label?.contains("\u{202E}") == false)
        #expect(label?.contains("\n") == false)
        #expect(QuestionMetadataPresentation.label(" \n\u{202E}") == nil)
        #expect(QuestionMetadataPresentation.label(nil) == nil)
    }
}
