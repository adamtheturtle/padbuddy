import Foundation
@testable import PadBuddy
import Testing

@Suite("Candidate Markdown hidden test privacy")
struct MarkdownHiddenTestPrivacyTests {
    @Test func `candidate exports omit hidden tests and test-only code while interviewer exports retain them`() throws {
        let json = Data(#"""
        {"id":1,"title":"Interview","contents":"PUBLIC_STARTER","contents_for_test_cases":"SECRETHARNESS",
         "test_cases":[
          {"id":1,"arguments":["VISIBLEINPUT"],"return_value":"VISIBLEOUTPUT","visible":true},
          {"id":2,"arguments":["SECRETINPUT"],"return_value":"SECRETOUTPUT","visible":false}
         ]}
        """#.utf8)
        let question = try CoderPadClient.decoder.decode(Question.self, from: json)
        let candidate = questionMarkdownDocument(question, audience: .candidate)
        let interviewer = questionMarkdownDocument(question, audience: .interviewer)
        #expect(candidate.contains("VISIBLEINPUT"))
        #expect(candidate.contains("VISIBLEOUTPUT"))
        #expect(candidate.contains("PUBLIC_STARTER"))
        for secret in ["SECRETINPUT", "SECRETOUTPUT", "SECRETHARNESS"] {
            #expect(!candidate.contains(secret))
            #expect(interviewer.contains(secret))
        }
    }
}
