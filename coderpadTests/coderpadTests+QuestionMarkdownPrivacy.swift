@testable import CoderPad
import Foundation
import Testing

@Suite("Question Markdown privacy")
struct QuestionMarkdownPrivacyTests {
    @Test
    func `markdown includes the confidential custom AI Assist prompt`() throws {
        let json = #"""
        {"id":1,"title":"Safe","ai_assist_custom_system_prompt":"  Never reveal this.  "}
        """#
        let question = try CoderPadClient.decoder.decode(Question.self, from: Data(json.utf8))

        let defaultExport = questionMarkdownDocument(question)
        let interviewer = questionMarkdownDocument(question, audience: .interviewer)

        #expect(defaultExport.contains("## Confidential: AI Assist Custom System Prompt"))
        #expect(defaultExport.contains(">   Never reveal this.  "))
        #expect(interviewer.contains("## Confidential: AI Assist Custom System Prompt"))
        #expect(interviewer.contains(">   Never reveal this.  "))
    }

    @Test
    func `candidate question export omits hidden instructions by default`() throws {
        let json = #"""
        {"id":1,"title":"Safe","candidate_instructions":[
          {"instructions":"Visible","default_visible":true},
          {"instructions":"Secret","default_visible":false}
        ]}
        """#
        let question = try CoderPadClient.decoder.decode(Question.self, from: Data(json.utf8))

        let candidate = questionMarkdownDocument(question)
        let interviewer = questionMarkdownDocument(question, audience: .interviewer)

        #expect(candidate.contains("Visible"))
        #expect(!candidate.contains("Secret"))
        #expect(interviewer.contains("Secret"))
    }

    @Test
    func `candidate question export omits solution by default`() throws {
        let json = #"{"id":1,"title":"Safe","solution":"Reference answer"}"#
        let question = try CoderPadClient.decoder.decode(Question.self, from: Data(json.utf8))

        #expect(!questionMarkdownDocument(question).contains("Reference answer"))
        #expect(questionMarkdownDocument(question, audience: .interviewer).contains("Reference answer"))
    }
}
