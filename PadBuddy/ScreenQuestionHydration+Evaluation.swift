extension ScreenQuestionHydration {
    static func input(_ source: ScreenEvaluationAcceptedAnswerDetails) throws
        -> ScreenEvaluationAcceptedAnswerInput {
        try ScreenEvaluationAcceptedAnswerInput(
            value: source.value,
            matchType: optional(source.matchType, as: ScreenEvaluationAcceptedAnswerInput.MatchType.self)
        )
    }

    static func input(_ source: ScreenTextAnswerMatchingDetails) throws -> ScreenTextAnswerMatchingInput {
        try ScreenTextAnswerMatchingInput(
            acceptedAnswers: source.acceptedAnswers.map { try $0.map(input) }
        )
    }

    static func input(_ source: ScreenChoiceSelectionDetails) throws -> ScreenChoiceSelectionInput {
        ScreenChoiceSelectionInput(
            correctChoiceIndexes: source.correctChoiceIndexes
        )
    }

    static func input(_ source: ScreenEvaluationDetails) throws -> ScreenEvaluationInput {
        try ScreenEvaluationInput(
            rubric: source.rubric.map(input),
            validationCode: source.validationCode.map(input),
            inputOutput: source.inputOutput.map(input),
            sqlQueryResultComparison: source.sqlQueryResultComparison.map(input),
            textAnswerMatching: source.textAnswerMatching.map(input),
            choiceSelection: source.choiceSelection.map(input)
        )
    }
}
