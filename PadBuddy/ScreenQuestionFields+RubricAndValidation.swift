import SwiftUI

extension ScreenQuestionFields {
    static func fields(_ value: Binding<ScreenRubricCriterionInput>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Self.localized(String(localized: "Label"), value: value.label)
            Self.text(String(localized: "Skill"), value: value.skill)
            Self.integer(String(localized: "Maximum points"), value: value.points)
            Self.integer(String(localized: "Weight"), value: value.weight)
            Self.enumeration(
                String(localized: "Review mode"),
                value: value.reviewMode,
                type: ScreenRubricCriterionInput.ReviewMode.self
            )
            Self.text(String(localized: "Description"), value: value.description)
        }
    }

    static func fields(_ value: Binding<ScreenRubricInput>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Self
                .array(String(localized: "Criteria"), value: value.criteria, make: ScreenRubricCriterionInput()) {
                    fields($0)
                }
        }
    }

    static func fields(_ value: Binding<ScreenValidationCodeTestCaseInput>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Self.localized(String(localized: "Label"), value: value.label)
            Self.text(String(localized: "Test identifier"), value: value.testIdentifier)
            Self.text(String(localized: "Skill"), value: value.skill)
            Self.integer(String(localized: "Maximum points"), value: value.points)
            Self.integer(String(localized: "Weight"), value: value.weight)
            Self.integer(String(localized: "Difficulty"), value: value.difficulty)
            Self.boolean(String(localized: "Contributes to score"), value: value.contributesToScore)
            Self.boolean(String(localized: "Visible to candidate"), value: value.visibleToCandidate)
        }
    }

    static func fields(_ value: Binding<ScreenValidationCodeInput>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Self.array(
                String(localized: "Test cases"),
                value: value.testCases,
                make: ScreenValidationCodeTestCaseInput()
            ) { fields($0) }
        }
    }
}
