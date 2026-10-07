extension ScreenQuestionHydration {
    static func input(_ source: ScreenProjectResourceDetails) throws -> ScreenProjectResourceInput {
        ScreenProjectResourceInput(
            version: source.version,
            resourceID: source.resourceID
        )
    }

    static func input(_ source: ScreenProjectDetails) throws -> ScreenProjectInput {
        try ScreenProjectInput(
            environment: source.environment.map(input),
            resources: source.resources.map { try $0.map(input) },
            aiAssistAdditionalInstructions: source.aiAssistAdditionalInstructions,
            aiAssistAllowed: source.aiAssistAllowed
        )
    }

    static func input(_ source: ScreenEnvironmentDetails) throws -> ScreenEnvironmentInput {
        ScreenEnvironmentInput(
            version: source.version,
            environmentID: source.environmentID
        )
    }

    static func input(_ source: ScreenDatabaseEngineDetails) throws -> ScreenDatabaseEngineInput {
        ScreenDatabaseEngineInput(
            version: source.version,
            engineID: source.engineID
        )
    }
}
