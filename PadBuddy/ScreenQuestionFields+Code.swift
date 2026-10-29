import SwiftUI

extension ScreenQuestionFields {
    static func fields(_ value: Binding<ScreenFunctionSignatureInput>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Self.text(String(localized: "Name"), value: value.name)
            Self
                .array(String(localized: "Parameters"), value: value.parameters, make: [:]) {
                    ScreenQuestionSchemaMap(value: $0)
                }
            Self.schema(String(localized: "Return type"), value: value.returnType)
        }
    }

    static func fields(_ value: Binding<ScreenPossibleSolutionInput>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Self.text(String(localized: "Code"), value: value.code)
            Self.text(String(localized: "Programming language"), value: value.programmingLanguageID)
        }
    }

    static func fields(_ value: Binding<ScreenCodeInput>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Self.included(
                String(localized: "Environment"),
                value: value.environment,
                make: ScreenEnvironmentInput()
            ) { fields($0) }
            Self.enumeration(String(localized: "Mode"), value: value.mode, type: ScreenCodeInput.Mode.self)
            Self.text(String(localized: "Programming language"), value: value.programmingLanguageID)
            Self.text(String(localized: "Candidate test code"), value: value.candidateTestCode)
            Self.text(String(localized: "Validator code"), value: value.validatorCode)
            Self.integer(String(localized: "Timeout in milliseconds"), value: value.timeoutMS)
            Self.included(
                String(localized: "Database engine"),
                value: value.databaseEngine,
                make: ScreenDatabaseEngineInput()
            ) { fields($0) }
            Self.text(String(localized: "Database setup script"), value: value.databaseSetupScript)
            Self.text(String(localized: "Starter code"), value: value.starterCode)
            Self.included(
                String(localized: "Function signature"),
                value: value.functionSignature,
                make: ScreenFunctionSignatureInput()
            ) { fields($0) }
            Self.included(
                String(localized: "Possible solution"),
                value: value.possibleSolution,
                make: ScreenPossibleSolutionInput()
            ) { fields($0) }
            Self.boolean(
                String(localized: "Show function signature in statement"),
                value: value.showFunctionSignatureInStatement
            )
        }
    }
}
