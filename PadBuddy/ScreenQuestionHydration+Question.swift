extension ScreenQuestionHydration {
    static func input(_ source: ScreenQuestionDetails) throws -> ScreenQuestionSave {
        try ScreenQuestionSave(
            type: required(source.type, as: ScreenQuestionSave.QuestionType.self),
            domain: source.domain,
            durationSeconds: source.durationSeconds,
            difficulty: optional(source.difficulty, as: ScreenQuestionSave.Difficulty.self),
            points: source.points,
            title: source.title,
            statement: source.statement,
            locales: source.locales,
            skill: source.skill,
            teamID: source.teamID,
            automaticallySelectable: source.automaticallySelectable,
            comment: source.comment,
            evaluation: source.evaluation.map(input),
            codeDetails: source.codeDetails.map(input),
            mcqDetails: source.mcqDetails.map(input),
            textDetails: source.textDetails.map(input),
            videoDetails: source.videoDetails.map(input),
            projectDetails: source.projectDetails.map(input)
        )
    }
}
