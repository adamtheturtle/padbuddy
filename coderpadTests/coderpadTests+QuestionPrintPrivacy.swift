@testable import CoderPad
import Foundation
import Testing

@Suite("Question print privacy")
struct QuestionPrintPrivacyTests {
    @Test
    func `candidate print omits hidden instructions and solution`() throws {
        let question = try decodedQuestion()

        #expect(QuestionPrintDocument.includedInstructions(question.candidateInstructions, audience: .candidate)
            .map(\.instructions) == ["Visible"])
        #expect(QuestionPrintDocument.includedSolution(question.solution, audience: .candidate).isEmpty)
    }

    @Test
    func `interviewer print explicitly includes confidential content`() throws {
        let question = try decodedQuestion()

        #expect(QuestionPrintDocument.includedInstructions(question.candidateInstructions, audience: .interviewer)
            .map(\.instructions) == ["Visible", "Hidden"])
        #expect(QuestionPrintDocument.includedSolution(question.solution, audience: .interviewer) == "Secret")
    }

    private func decodedQuestion() throws -> Question {
        let json = #"{"id":1,"title":"Safe","candidate_instructions":[{"instructions":"Visible","default_visible":true},{"instructions":"Hidden","default_visible":false}],"solution":"Secret"}"#
        return try CoderPadClient.decoder.decode(Question.self, from: Data(json.utf8))
    }
}
