@testable import PadBuddy
import Testing

@Suite("Question AI Assist prompt previews")
struct QuestionAIAssistPreviewTests {
    @Test func `oversized prompts are bounded before display and flagged as partial`() {
        let preview = QuestionAIAssistPreview.make(String(repeating: "word ", count: 100_000))
        #expect(preview?.text.unicodeScalars.count == 16385)
        #expect(preview?.isTruncated == true)
    }

    @Test func `ordinary prompts preserve text and blank prompts remain unavailable`() {
        #expect(QuestionAIAssistPreview.make("Explain arrays")?.text == "Explain arrays")
        #expect(QuestionAIAssistPreview.make("Explain arrays")?.isTruncated == false)
        #expect(QuestionAIAssistPreview.make(" \n ") == nil)
        #expect(QuestionAIAssistPreview.make(nil) == nil)
        // A long whitespace prefix must not claim that the full custom prompt is absent.
        #expect(QuestionAIAssistPreview.make(String(repeating: " ", count: 20000) + "Prompt")?.isTruncated == true)
    }
}
