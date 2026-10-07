extension ScreenQuestionHydration {
    static func input(_ source: ScreenInputOutputTestCaseDetails) throws -> ScreenInputOutputTestCaseInput {
        ScreenInputOutputTestCaseInput(
            label: source.label,
            input: source.input,
            output: source.output,
            skill: source.skill,
            points: source.points,
            weight: source.weight,
            difficulty: source.difficulty,
            contributesToScore: source.contributesToScore,
            visibleToCandidate: source.visibleToCandidate,
            timeoutMSByProgrammingLanguageID: source.timeoutMSByProgrammingLanguageID
        )
    }

    static func input(_ source: ScreenInputOutputDetails) throws -> ScreenInputOutputEvaluationInput {
        try ScreenInputOutputEvaluationInput(
            testCases: source.testCases.map { try $0.map(input) }
        )
    }

    static func input(_ source: ScreenQueryComparisonRulesDetails) throws -> ScreenQueryComparisonRulesInput {
        ScreenQueryComparisonRulesInput(
            rowOrderMatters: source.rowOrderMatters,
            columnOrderMatters: source.columnOrderMatters,
            compareAllTables: source.compareAllTables
        )
    }

    static func input(_ source: ScreenSQLQueryResultComparisonDetails) throws
        -> ScreenSQLQueryResultComparisonInput {
        try ScreenSQLQueryResultComparisonInput(
            referenceQuery: source.referenceQuery,
            comparison: source.comparison.map(input)
        )
    }
}
