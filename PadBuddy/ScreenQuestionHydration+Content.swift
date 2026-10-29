extension ScreenQuestionHydration {
    static func input(_ source: ScreenQuestionChoiceDetails) throws -> ScreenQuestionChoiceInput {
        ScreenQuestionChoiceInput(
            label: source.label
        )
    }

    static func input(_ source: ScreenMCQDetails) throws -> ScreenMCQInput {
        try ScreenMCQInput(
            choices: source.choices.map { try $0.map(input) },
            selectionMode: optional(source.selectionMode, as: ScreenMCQInput.SelectionMode.self),
            randomizeChoices: source.randomizeChoices
        )
    }

    static func input(_ source: ScreenTextDetails) throws -> ScreenTextInput {
        try ScreenTextInput(
            evaluationMode: optional(source.evaluationMode, as: ScreenTextInput.EvaluationMode.self)
        )
    }

    static func input(_ source: ScreenVideoDetails) throws -> ScreenVideoInput {
        try ScreenVideoInput(
            recordingMedia: optional(source.recordingMedia, as: ScreenVideoInput.RecordingMedia.self)
        )
    }
}
