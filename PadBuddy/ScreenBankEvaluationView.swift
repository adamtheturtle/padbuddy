import SwiftUI

struct ScreenBankEvaluationView: View {
    let evaluation: ScreenEvaluationDetails
    let locale: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            rubric
            testReport
            inputOutput
            answerMatching
            if let reference = evaluation.sqlQueryResultComparison?.referenceQuery {
                ScreenBankCodeBlock(title: "Reference Query", text: reference)
            }
            if let comparison = evaluation.sqlQueryResultComparison?.comparison {
                if let value = comparison.rowOrderMatters {
                    flag("Row order matters", value: value)
                }
                if let value = comparison.columnOrderMatters {
                    flag("Column order matters", value: value)
                }
                if let value = comparison.compareAllTables {
                    flag("Compare all tables", value: value)
                }
            }
        }
    }

    @ViewBuilder private var rubric: some View {
        if let criteria = evaluation.rubric?.criteria {
            DetailSection(title: "Evaluation Rubric", systemImage: "list.clipboard") {
                ForEach(criteria.indices.prefix(200), id: \.self) { index in
                    let criterion = criteria[index]
                    if let label = ScreenBankText.localized(criterion.label, locale: locale) {
                        MarkdownText(label)
                    }
                    if let description = criterion.description {
                        Text(verbatim: description)
                    }
                    if let skill = criterion.skill {
                        LabeledContent("Skill", value: skill)
                    }
                    if let points = criterion.points {
                        LabeledContent("Points", value: String(points))
                    }
                    if let weight = criterion.weight {
                        LabeledContent("Weight", value: String(weight))
                    }
                    if let mode = criterion.reviewMode {
                        LabeledContent("Review mode", value: mode)
                    }
                    Divider()
                }
                if criteria.count > 200 {
                    Text("Some evaluation items are too numerous to display.")
                }
            }
        }
    }

    @ViewBuilder private var testReport: some View {
        if let cases = evaluation.testReport?.testCases {
            DetailSection(title: "Project Test Cases", systemImage: "checkmark.seal") {
                ForEach(cases.indices.prefix(200), id: \.self) { index in
                    let test = cases[index]
                    if let label = ScreenBankText.localized(test.label, locale: locale) {
                        MarkdownText(label)
                    }
                    if let identifier = test.testIdentifier ?? test.key {
                        Text(verbatim: identifier)
                    }
                    if let points = test.points {
                        LabeledContent("Points", value: String(points))
                    }
                }
                if cases.count > 200 {
                    Text("Some evaluation items are too numerous to display.")
                }
            }
        }
        if let cases = evaluation.validationCode?.testCases {
            DetailSection(title: "Code Test Cases", systemImage: "checkmark.seal") {
                ForEach(cases.indices.prefix(200), id: \.self) { index in
                    let test = cases[index]
                    if let label = ScreenBankText.localized(test.label, locale: locale) {
                        MarkdownText(label)
                    }
                    if let identifier = test.testIdentifier {
                        Text(verbatim: identifier)
                    }
                    if let points = test.points {
                        LabeledContent("Points", value: String(points))
                    }
                    if let contributes = test.contributesToScore {
                        flag("Contributes to score", value: contributes)
                    }
                    if let visible = test.visibleToCandidate {
                        flag("Visible to candidate", value: visible)
                    }
                }
                if cases.count > 200 {
                    Text("Some evaluation items are too numerous to display.")
                }
            }
        }
    }

    @ViewBuilder private var inputOutput: some View {
        if let cases = evaluation.inputOutput?.testCases {
            DetailSection(title: "Input and Output Tests", systemImage: "arrow.left.arrow.right") {
                ForEach(cases.indices.prefix(200), id: \.self) { index in
                    let test = cases[index]
                    if let label = ScreenBankText.localized(test.label, locale: locale) {
                        MarkdownText(label)
                    }
                    ScreenBankCodeBlock(title: "Input", text: test.input)
                    ScreenBankCodeBlock(title: "Expected Output", text: test.output)
                    if let points = test.points {
                        LabeledContent("Points", value: String(points))
                    }
                    if let visible = test.visibleToCandidate {
                        flag("Visible to candidate", value: visible)
                    }
                    Divider()
                }
                if cases.count > 200 {
                    Text("Some evaluation items are too numerous to display.")
                }
            }
        }
    }

    @ViewBuilder private var answerMatching: some View {
        if let answers = evaluation.textAnswerMatching?.acceptedAnswers {
            DetailSection(title: "Accepted Answers", systemImage: "checkmark.bubble") {
                ForEach(answers.indices.prefix(200), id: \.self) { index in
                    let answer = answers[index]
                    Text(verbatim: [answer.value, answer.matchType].compactMap(\.self).joined(separator: " · "))
                }
                if answers.count > 200 {
                    Text("Some evaluation items are too numerous to display.")
                }
            }
        }
        if let indices = evaluation.choiceSelection?.correctChoiceIndexes {
            LabeledContent("Correct choice indices", value: indices.map(String.init).joined(separator: ", "))
        }
    }

    private func flag(_ label: LocalizedStringKey, value: Bool) -> some View {
        LabeledContent(label) { Text(value ? "Yes" : "No") }
    }
}
