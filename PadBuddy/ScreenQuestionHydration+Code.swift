extension ScreenQuestionHydration {
    static func input(_ source: ScreenPossibleSolutionDetails) throws -> ScreenPossibleSolutionInput {
        ScreenPossibleSolutionInput(
            code: source.code,
            programmingLanguageID: source.programmingLanguageID
        )
    }

    static func input(_ source: ScreenCodeDetails) throws -> ScreenCodeInput {
        try ScreenCodeInput(
            environment: source.environment.map(input),
            mode: optional(source.mode, as: ScreenCodeInput.Mode.self),
            programmingLanguageID: source.programmingLanguageID,
            candidateTestCode: source.candidateTestCode,
            validatorCode: source.validatorCode,
            timeoutMS: source.timeoutMS,
            databaseEngine: source.databaseEngine.map(input),
            databaseSetupScript: source.databaseSetupScript,
            starterCode: source.starterCode,
            functionSignature: source.functionSignature.map(input),
            possibleSolution: source.possibleSolution.map(input),
            showFunctionSignatureInStatement: source.showFunctionSignatureInStatement
        )
    }

    static func input(_ source: ScreenFunctionSignatureDetails) throws -> ScreenFunctionSignatureInput {
        ScreenFunctionSignatureInput(
            name: source.name,
            parameters: source.parameters,
            returnType: source.returnType
        )
    }
}
