@testable import CoderPad
import Foundation
import Testing

@Suite("Question Markdown privacy")
struct QuestionMarkdownPrivacyTests {
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
