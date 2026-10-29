import SwiftUI

extension ScreenQuestionFields {
    static func fields(_ value: Binding<ScreenQuestionChoiceInput>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Self.localized(String(localized: "Label"), value: value.label)
        }
    }

    static func fields(_ value: Binding<ScreenMCQInput>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Self
                .array(String(localized: "Choices"), value: value.choices, make: ScreenQuestionChoiceInput()) {
                    fields($0)
                }
            Self.enumeration(
                String(localized: "Selection mode"),
                value: value.selectionMode,
                type: ScreenMCQInput.SelectionMode.self
            )
            Self.boolean(String(localized: "Randomize choices"), value: value.randomizeChoices)
        }
    }

    static func fields(_ value: Binding<ScreenTextInput>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Self.enumeration(
                String(localized: "Evaluation mode"),
                value: value.evaluationMode,
                type: ScreenTextInput.EvaluationMode.self
            )
        }
    }

    static func fields(_ value: Binding<ScreenVideoInput>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Self.enumeration(
                String(localized: "Recording media"),
                value: value.recordingMedia,
                type: ScreenVideoInput.RecordingMedia.self
            )
        }
    }
}
