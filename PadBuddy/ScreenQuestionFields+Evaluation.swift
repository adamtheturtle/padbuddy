import SwiftUI

extension ScreenQuestionFields {
    static func fields(_ value: Binding<ScreenChoiceSelectionInput>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Self
                .array(String(localized: "Correct choice indexes"), value: value.correctChoiceIndexes, make: 0) {
                    ScreenQuestionIntegerField(value: $0)
                }
        }
    }

    static func fields(_ value: Binding<ScreenEvaluationInput>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Self
                .included(String(localized: "Rubric"), value: value.rubric, make: ScreenRubricInput()) {
                    fields($0)
                }
            Self.included(
                String(localized: "Validation code"),
                value: value.validationCode,
                make: ScreenValidationCodeInput()
            ) { fields($0) }
            Self.included(
                String(localized: "Input and output tests"),
                value: value.inputOutput,
                make: ScreenInputOutputEvaluationInput()
            ) { fields($0) }
            Self.included(
                String(localized: "Sql query result comparison"),
                value: value.sqlQueryResultComparison,
                make: ScreenSQLQueryResultComparisonInput()
            ) { fields($0) }
            Self.included(
                String(localized: "Text answer matching"),
                value: value.textAnswerMatching,
                make: ScreenTextAnswerMatchingInput()
            ) { fields($0) }
            Self.included(
                String(localized: "Choice selection"),
                value: value.choiceSelection,
                make: ScreenChoiceSelectionInput()
            ) { fields($0) }
        }
    }

    static func fields(_ value: Binding<ScreenEvaluationAcceptedAnswerInput>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Self.text(String(localized: "Value"), value: value.value)
            Self.enumeration(
                String(localized: "Match type"),
                value: value.matchType,
                type: ScreenEvaluationAcceptedAnswerInput.MatchType.self
            )
        }
    }

    static func fields(_ value: Binding<ScreenTextAnswerMatchingInput>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Self.array(
                String(localized: "Accepted answers"),
                value: value.acceptedAnswers,
                make: ScreenEvaluationAcceptedAnswerInput()
            ) { fields($0) }
        }
    }
}
