@testable import PadBuddy
import Testing

@Suite("Question content previews")
struct QuestionContentPreviewTests {
    @Test func `large values have bounded previews and preserve code whitespace`() {
        let preview = QuestionContentPreview("a\n\tb\u{202E}" + String(repeating: "x", count: 10000))
        #expect(preview.text.unicodeScalars.count == 2049)
        #expect(preview.text.hasPrefix("a\n\tb "))
        #expect(preview.isTruncated)
        #expect(!QuestionContentPreview("small").isTruncated)
    }

    @Test func `arguments are bounded in count and size before joining`() {
        let arguments = Array(repeating: String(repeating: "x", count: 10000), count: 10000)
        let preview = QuestionArgumentPreview(arguments)
        #expect(preview.text.unicodeScalars.count <= 16 * 129 + 15 * 2)
        #expect(preview.isTruncated)
        #expect(QuestionArgumentPreview(["1", "2"]).text == "1, 2")
        #expect(!QuestionArgumentPreview(["1", "2"]).isTruncated)
        #expect(!QuestionArgumentPreview(nil).isTruncated)
    }

    @Test func `explicit full value copying has a byte budget including Unicode`() {
        #expect(QuestionContentPreview.canCopyFullValue(String(repeating: "a", count: 65536)))
        #expect(!QuestionContentPreview.canCopyFullValue(String(repeating: "a", count: 65537)))
        #expect(!QuestionContentPreview.canCopyFullValue(String(repeating: "😀", count: 20000)))
    }
}
