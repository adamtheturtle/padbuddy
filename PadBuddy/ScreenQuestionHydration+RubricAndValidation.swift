extension ScreenQuestionHydration {
    static func input(_ source: ScreenRubricDetails) throws -> ScreenRubricInput {
        try ScreenRubricInput(
            criteria: source.criteria.map { try $0.map(input) }
        )
    }

    static func input(_ source: ScreenValidationCodeTestCaseDetails) throws -> ScreenValidationCodeTestCaseInput {
        ScreenValidationCodeTestCaseInput(
            label: source.label,
            testIdentifier: source.testIdentifier,
            skill: source.skill,
            points: source.points,
            weight: source.weight,
            difficulty: source.difficulty,
            contributesToScore: source.contributesToScore,
            visibleToCandidate: source.visibleToCandidate
        )
    }

    static func input(_ source: ScreenValidationCodeDetails) throws -> ScreenValidationCodeInput {
        try ScreenValidationCodeInput(
            testCases: source.testCases.map { try $0.map(input) }
        )
    }

    static func input(_ source: ScreenRubricCriterionDetails) throws -> ScreenRubricCriterionInput {
        try ScreenRubricCriterionInput(
            label: source.label,
            skill: source.skill,
            points: source.points,
            weight: source.weight,
            reviewMode: optional(source.reviewMode, as: ScreenRubricCriterionInput.ReviewMode.self),
            description: source.description
        )
    }
}
