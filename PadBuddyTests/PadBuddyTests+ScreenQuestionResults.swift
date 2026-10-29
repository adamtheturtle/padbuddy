import Foundation
@testable import PadBuddy
import SwiftUI
import Testing

@Suite("Screen question results")
struct ScreenQuestionResultsTests {
    @Test @MainActor
    func `API results retain UUID order all submission types grading warnings and epoch milliseconds`(
    ) async throws {
        let client = ScreenClient.mock(key: "native-results-" + UUID().uuidString)
        let session = try await client.getTest(id: 5001)
        #expect(session.detailedQuestions.compactMap(\.type) == ["PROJECT", "CODE", "GAME", "TEXT", "MCQ",
                                                                 "FILE_UPLOAD", "VIDEO", "MULTI"])
        let project = try #require(session.detailedQuestions.first)
        let rows = flattened(ScreenResultRows.rows(project))
        #expect(rows["Awarded points"] == "18")
        #expect(rows["Timed out"] == "False")
        #expect(rows["Marked as cheated by recruiter"] == "False")
        #expect(rows["Time outside environment (seconds)"] == "0")
        #expect(rows["Environment exit count"] == "0")
        #expect(rows["First access (epoch milliseconds)"] == "1685545371216")
        #expect(rows["Warnings/Item 1/Type"] == "CUSTOM_COMPANY_WARNING")
        #expect(rows["Warnings/Item 1/Level"] == "UNUSUAL_ACTIVITY")
        #expect(rows["Evaluation/Rubric/Criteria/Item 1/Outcome"] == "PENDING_MANUAL_REVIEW")
        #expect(rows["Evaluation/Rubric/Criteria/Item 1/Awarded points"] == "Not provided")
        #expect(rows["Evaluation/Rubric/Criteria/Item 1/AI review/No recommendation reason"]
            == "CONFIDENCE_SCORE_TOO_LOW")
        let count = rows["Answer/Submitted project/AI Assist conversation count"]
        #expect(count == "0")
        for question in session.detailedQuestions {
            let resultRows = ScreenResultRows.rows(question)
            let native = ImageRenderer(content: ScreenResultRowsView(rows: resultRows).frame(width: 600))
            #expect(native.cgImage != nil)
        }
        #expect(ImageRenderer(content: ScreenQuestionResultsView(session: session).frame(width: 600))
            .cgImage != nil)
    }

    @Test @MainActor
    func `missing answers empty evaluations zero scores false flags and future kinds remain distinct`() throws {
        let question = try JSONDecoder().decode(ScreenDetailedQuestion.self, from: Data(#"""
        {"id":"4143ca74-2f0e-4151-90d6-e1428739450b","type":"FUTURE","max_points":0,"awarded_points":0,
         "timed_out":false,"warnings":[],"evaluation":{"rubric":{"criteria":[]}},
         "answer_status":"FUTURE_STATUS","grading_status":"AWAITING_REVIEW"}
        """#.utf8))
        let rows = flattened(ScreenResultRows.rows(question))
        #expect(rows["Maximum points"] == "0")
        #expect(rows["Awarded points"] == "0")
        #expect(rows["Timed out"] == "False")
        #expect(rows["Warnings"] == "[empty]")
        #expect(rows["Evaluation/Rubric/Criteria"] == "[empty]")
        #expect(rows["Answer"] == "Not provided")
        #expect(rows["Answer status"] == "FUTURE_STATUS")
        #expect(rows["Grading status"] == "AWAITING_REVIEW")
        #expect(ImageRenderer(content: ScreenDetailedQuestionResultView(question: question).frame(width: 600))
            .cgImage != nil)
    }

    @Test @MainActor
    func `mixed integer summaries and UUID details preserve namespaces and original ordering`() throws {
        let session = try JSONDecoder().decode(ScreenTestSession.self, from: Data(#"""
        {"id":5001,"status":"completed","timer_type":"PER_QUESTION","questions":[
         {"id":12,"last_activity_time":1685545373216},
         {"id":"4143ca74-2f0e-4151-90d6-e1428739450b","type":"TEXT",
          "answer":{"text_answer":{"text":"Candidate answer"}}},
         {"id":13}]}
        """#.utf8))
        #expect(session.questions.map(\.id) == [12, 13])
        #expect(session.detailedQuestions
            .map { $0.id.uuidString.lowercased() } == ["4143ca74-2f0e-4151-90d6-e1428739450b"])
        #expect(session.timerType == "PER_QUESTION")
        guard case .summary = session.questionEntries[0], case .detailed = session.questionEntries[1],
              case .summary = session.questionEntries[2] else { Issue.record("Question order changed"); return }

        #expect(flattened(ScreenResultRows.rows(session.detailedQuestions[0]))["Answer/Text submission/Text"]
            == "Candidate answer")
        #expect(ImageRenderer(content: ScreenQuestionResultsView(session: session).frame(width: 600))
            .cgImage != nil)
    }

    @Test @MainActor
    func `candidate code preserves line endings and multiple choice indexes start at zero`() throws {
        let code = try JSONDecoder().decode(ScreenCodeAnswer.self, from: Data(#"""
        {"code":"print(0)\r\n","programming_language_id":"Python3"}
        """#.utf8))
        #expect(ScreenResultRows.rows(code) == [
            .value("Code", "print(0)\r\n"),
            .value("Programming language", "Python3")
        ])
        let choice = try JSONDecoder().decode(
            ScreenMCQAnswer.self,
            from: Data(#"{"selected_choice_indexes":[0,2]}"#.utf8)
        )
        #expect(ScreenResultRows.rows(choice) == [.group("Selected choice indexes (starting at 0)", [
            .group("Item 1", [.value("Value", "0")]), .group("Item 2", [.value("Value", "2")])
        ])])
    }

    @Test @MainActor
    func `long result arrays disclose the display limit and keep the first two hundred entries`() {
        let rows = ScreenResultRows.values("Values", Array(0 ... 200))
        guard case let .group(_, children) = rows else { Issue.record("Expected result group"); return }

        #expect(children.count == 201)
        #expect(children.first == .group("Item 1", [.value("Value", "0")]))
        #expect(children[199] == .group("Item 200", [.value("Value", "199")]))
        #expect(children.last == .value("Display limit", "Only the first 200 entries are shown."))
    }

    private func flattened(_ rows: [ScreenResultRow], prefix: String = "") -> [String: String] {
        rows.reduce(into: [:]) { output, row in
            switch row {
            case let .value(label, value): output[prefix + label] = value
            case let .group(label, children):
                if children.isEmpty {
                    output[prefix + label] = "[empty]"
                }
                output.merge(flattened(children, prefix: prefix + label + "/")) { _, new in new }
            }
        }
    }
}
