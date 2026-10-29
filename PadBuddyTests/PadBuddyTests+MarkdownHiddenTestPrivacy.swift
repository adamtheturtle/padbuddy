import Foundation
@testable import PadBuddy
import Testing

@Suite("Candidate Markdown hidden test privacy")
struct MarkdownHiddenTestPrivacyTests {
    @Test func `candidate exports omit hidden tests and test-only code while interviewer exports retain them`() throws {
        let json = Data(#"""
        {"id":1,"title":"Interview","contents":"PUBLIC_STARTER","contents_for_test_cases":"SECRET_HARNESS",
         "test_cases":[
          {"id":1,"arguments":["VISIBLE_INPUT"],"return_value":"VISIBLE_OUTPUT","visible":true},
          {"id":2,"arguments":["SECRET_INPUT"],"return_value":"SECRET_OUTPUT","visible":false}
         ]}
        """#.utf8)
        let question = try CoderPadClient.decoder.decode(Question.self, from: json)
        let candidate = questionMarkdownDocument(question, audience: .candidate)
        let interviewer = questionMarkdownDocument(question, audience: .interviewer)
        #expect(candidate.contains("VISIBLE_INPUT"))
        #expect(candidate.contains("VISIBLE_OUTPUT"))
        #expect(candidate.contains("PUBLIC_STARTER"))
        for secret in ["SECRET_INPUT", "SECRET_OUTPUT", "SECRET_HARNESS"] {
            #expect(!candidate.contains(secret))
            #expect(interviewer.contains(secret))
        }
    }
}
