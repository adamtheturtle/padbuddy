import Foundation
@testable import PadBuddy
import SwiftUI
import Testing

@Suite("Screen code question editing")
struct ScreenQuestionCodeHydrationTests {
    @Test @MainActor
    func `code edits retain function signatures database resources and every writable evaluation block`(
    ) async throws {
        let client = ScreenClient.mock(key: "authoring-code-" + UUID().uuidString)
        let original = ScreenQuestionSave(
            type: .code, domain: "Backend", difficulty: .hard, title: ["en": "Query"],
            evaluation: ScreenEvaluationInput(
                validationCode: ScreenValidationCodeInput(testCases: [ScreenValidationCodeTestCaseInput(
                    label: ["en": "Validation"], testIdentifier: "case-1", skill: "SQL", points: 0, weight: 0,
                    difficulty: 0, contributesToScore: false, visibleToCandidate: false
                )]),
                inputOutput: ScreenInputOutputEvaluationInput(testCases: [ScreenInputOutputTestCaseInput(
                    label: ["en": "Input"], input: "0", output: "1", points: 0, contributesToScore: false,
                    visibleToCandidate: false, timeoutMSByProgrammingLanguageID: ["C++": 1000]
                )]),
                sqlQueryResultComparison: ScreenSQLQueryResultComparisonInput(
                    referenceQuery: "SELECT 1", comparison: ScreenQueryComparisonRulesInput(
                        rowOrderMatters: false, columnOrderMatters: false, compareAllTables: false
                    )
                )
            ),
            codeDetails: ScreenCodeInput(
                environment: ScreenEnvironmentInput(version: "v1", environmentID: "database"),
                mode: .singleLanguage, programmingLanguageID: "SQL", candidateTestCode: "SELECT 0",
                validatorCode: "check()", timeoutMS: 0,
                databaseEngine: ScreenDatabaseEngineInput(version: "15", engineID: "postgres"),
                databaseSetupScript: "CREATE TABLE demo (id INT)", starterCode: "SELECT",
                functionSignature: ScreenFunctionSignatureInput(
                    name: "solve", parameters: [["name": .string("input"), "type": .string("integer")]],
                    returnType: ["type": .string("integer"), "nullable": .bool(false)]
                ),
                possibleSolution: ScreenPossibleSolutionInput(code: "SELECT 1", programmingLanguageID: "SQL"),
                showFunctionSignatureInStatement: false
            )
        )
        let created = try await client.createQuestion(original)
        let hydrated = try ScreenQuestionHydration.editable(created.question)
        #expect(hydrated == original)
        let model = ScreenQuestionAuthoringModel()
        await model.prepare(
            questionID: created.question.id,
            client: client,
            identity: ScreenBankIdentity(accountID: UUID(), clientIdentity: client.taskIdentity)
        )
        model.draft.title?["en"] = "Updated query"
        #expect(await model.save(client: client, isCurrent: { true }) == created.question.id)
        let updated = try await client.getQuestion(id: created.question.id)
        let saved = try ScreenQuestionHydration.editable(updated)
        #expect(saved.codeDetails == original.codeDetails)
        #expect(saved.evaluation == original.evaluation)
        #expect(saved.title == ["en": "Updated query"])
    }

    @Test @MainActor
    func `native forms render all writable content types without a raw payload editor`() {
        let views: [AnyView] = [
            AnyView(ScreenQuestionFields.fields(.constant(ScreenMCQInput(
                choices: [ScreenQuestionChoiceInput(label: ["en": "First", "es": "Primera"])],
                selectionMode: .multiple, randomizeChoices: false
            )))),
            AnyView(ScreenQuestionFields.fields(.constant(ScreenTextInput(evaluationMode: .automatic)))),
            AnyView(ScreenQuestionFields.fields(.constant(ScreenVideoInput(recordingMedia: .audio)))),
            AnyView(ScreenQuestionFields.fields(.constant(ScreenProjectInput(
                resources: [ScreenProjectResourceInput(version: "1", resourceID: "resource")],
                aiAssistAdditionalInstructions: "Explain changes", aiAssistAllowed: false
            ))))
        ]
        for view in views {
            #expect(ImageRenderer(content: view.frame(width: 600)).cgImage != nil)
        }
    }
}
