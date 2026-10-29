import Foundation
@testable import PadBuddy
import Testing

@Suite("Candidate Markdown system prompt privacy")
struct MarkdownSystemPromptPrivacyTests {
    @Test func `candidate exports omit the confidential system prompt and interviewer exports retain it`() throws {
        let json = Data(#"{"id":1,"title":"Interview","ai_assist_custom_system_prompt":"SECRET_SYSTEM_PROMPT"}"#.utf8)
        let question = try CoderPadClient.decoder.decode(Question.self, from: json)
        #expect(!questionMarkdownDocument(question, audience: .candidate).contains("SECRET_SYSTEM_PROMPT"))
        #expect(!questionMarkdownDocument(question).contains("SECRET_SYSTEM_PROMPT"))
        #expect(questionMarkdownDocument(question, audience: .interviewer).contains("SECRET_SYSTEM_PROMPT"))
    }
}
