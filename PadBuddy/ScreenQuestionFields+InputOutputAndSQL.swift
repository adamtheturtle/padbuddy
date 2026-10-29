import SwiftUI

extension ScreenQuestionFields {
    static func fields(_ value: Binding<ScreenInputOutputTestCaseInput>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Self.localized(String(localized: "Label"), value: value.label)
            Self.text(String(localized: "Input"), value: value.input)
            Self.text(String(localized: "Output"), value: value.output)
            Self.text(String(localized: "Skill"), value: value.skill)
            Self.integer(String(localized: "Maximum points"), value: value.points)
            Self.integer(String(localized: "Weight"), value: value.weight)
            Self.integer(String(localized: "Difficulty"), value: value.difficulty)
            Self.boolean(String(localized: "Contributes to score"), value: value.contributesToScore)
            Self.boolean(String(localized: "Visible to candidate"), value: value.visibleToCandidate)
            Self.timeouts(
                String(localized: "Timeout by programming language"),
                value: value.timeoutMSByProgrammingLanguageID
            )
        }
    }

    static func fields(_ value: Binding<ScreenInputOutputEvaluationInput>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Self.array(
                String(localized: "Test cases"),
                value: value.testCases,
                make: ScreenInputOutputTestCaseInput()
            ) { fields($0) }
        }
    }

    static func fields(_ value: Binding<ScreenQueryComparisonRulesInput>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Self.boolean(String(localized: "Row order matters"), value: value.rowOrderMatters)
            Self.boolean(String(localized: "Column order matters"), value: value.columnOrderMatters)
            Self.boolean(String(localized: "Compare all tables"), value: value.compareAllTables)
        }
    }

    static func fields(_ value: Binding<ScreenSQLQueryResultComparisonInput>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Self.text(String(localized: "Reference query"), value: value.referenceQuery)
            Self.included(
                String(localized: "Comparison"),
                value: value.comparison,
                make: ScreenQueryComparisonRulesInput()
            ) { fields($0) }
        }
    }
}
