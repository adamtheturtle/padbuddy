import Foundation
@testable import PadBuddy
import SwiftUI
import Testing

@Suite("Screen question authoring")
struct ScreenQuestionAuthoringTests {
    @Test @MainActor
    func `all six types create and update with localized content and explicit false and zero`() async throws {
        let client = ScreenClient.mock(key: "authoring-types-" + UUID().uuidString)
        let identity = ScreenBankIdentity(accountID: UUID(), clientIdentity: client.taskIdentity)
        for type in ScreenQuestionSave.QuestionType.allCases {
            let model = ScreenQuestionAuthoringModel()
            await model.prepare(questionID: nil, client: client, identity: identity)
            model.changeType(type)
            model.draft.title = ["en": "Original", "es": "Original en español"]
            model.draft.statement = ["en": "Explain your answer", "es": "Explica tu respuesta"]
            model.draft.points = 0
            model.draft.durationSeconds = 0
            model.draft.automaticallySelectable = false
            model.draft.locales = ["en", "es"]
            let id = try #require(await model.save(client: client, isCurrent: { true }))
            #expect(model.savedID == id)
            #expect(model.error == nil)
            let created = try await client.getQuestion(id: id)
            #expect(created.type == type.rawValue)
            #expect(created.points == 0)
            #expect(created.automaticallySelectable == false)
            #expect(created.title == model.draft.title)
            #expect(await model.save(client: client, isCurrent: { true }) == nil)
            let editor = ScreenQuestionAuthoringModel()
            await editor.prepare(questionID: id, client: client, identity: identity)
            #expect(editor.ready)
            editor.draft.title?["en"] = "Edited"
            #expect(await editor.save(client: client, isCurrent: { true }) == id)
            let updated = try await client.getQuestion(id: id)
            #expect(updated.title == ["en": "Edited", "es": "Original en español"])
            #expect(updated.statement == created.statement)
            #expect(updated.version == (created.version ?? 0) + 1)
        }
    }

    @Test @MainActor
    func `hydration preserves writable evaluation code and resource fields and excludes server report metadata`(
    ) throws {
        let data = Data(#"""
        {"id":"4143ca74-2f0e-4151-90d6-e1428739450b","version":9,"type":"PROJECT",
         "title":{"en":"Project","fr":"Projet"},"points":0,"automatically_selectable":false,
         "project_details":{"environment":{"environment_id":"node","version":"20"},
          "resources":[{"resource_id":"source","version":"v2"}],"ai_assist_allowed":false,
          "ai_assist_additional_instructions":"Keep tests","download_url":"https://example.com/archive"},
         "evaluation":{"test_report":{"test_cases":[{"key":"hidden","points":0}]},
          "rubric":{"criteria":[{"label":{"en":"Correctness"},"weight":0,"points":0,
          "review_mode":"AI_SUGGESTIONS","description":"Preserve detail"}]}},
         "creation_time":"2026-10-01","resources":[{"filename":"readme"}]}
        """#.utf8)
        let question = try JSONDecoder().decode(ScreenQuestionDetails.self, from: data)
        let draft = try ScreenQuestionHydration.editable(question)
        #expect(draft.projectDetails?.environment == ScreenEnvironmentInput(version: "20", environmentID: "node"))
        #expect(draft.projectDetails?.resources == [ScreenProjectResourceInput(
            version: "v2",
            resourceID: "source"
        )])
        #expect(draft.projectDetails?.aiAssistAllowed == false)
        #expect(draft.evaluation?.rubric?.criteria?.first?.reviewMode == .aiSuggestions)
        let value = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(draft))
        guard case let .object(fields) = value else { Issue.record("Expected writable object"); return }

        #expect(fields["id"] == nil)
        #expect(fields["version"] == nil)
        #expect(fields["resources"] == nil)
        #expect(fields["creation_time"] == nil)
        #expect(fields["evaluation"] == .object(["rubric": .object(["criteria": .array([
            .object(["label": .object(["en": .string("Correctness")]), "weight": .number(0),
                     "points": .number(0), "review_mode": .string("AI_SUGGESTIONS"),
                     "description": .string("Preserve detail")])
        ])])]))
    }

    @Test @MainActor
    func `bank questions unsupported types and unknown enum values cannot be edited destructively`() throws {
        let id = UUID().uuidString
        for fields in [#""type":"GAME""#, #""type":"CODE","from_coderpad_question_bank":true"#,
                       #""type":"MCQ","mcq_details":{"selection_mode":"FUTURE"}"#] {
            let bytes = Data(("{\"id\":\"" + id + "\"," + fields + "}").utf8)
            let question = try JSONDecoder().decode(ScreenQuestionDetails.self, from: bytes)
            #expect(throws: (any Error).self) { try ScreenQuestionHydration.editable(question) }
        }
    }

    @Test @MainActor
    func `failed writes preserve drafts and credentials are checked before and after a successful save`(
    ) async throws {
        let client = ScreenClient.mock(key: "authoring-context-" + UUID().uuidString)
        let identity = ScreenBankIdentity(accountID: UUID(), clientIdentity: client.taskIdentity)
        let model = ScreenQuestionAuthoringModel()
        await model.prepare(questionID: nil, client: client, identity: identity)
        model.draft.title = ["en": "Keep this draft"]
        let draft = model.draft
        #expect(await model.save(client: client, isCurrent: { false }) == nil)
        #expect(model.draft == draft)
        #expect(model.error != nil)
        var checks = 0
        #expect(await model.save(client: client, isCurrent: { checks += 1; return checks == 1 }) == nil)
        let id = try #require(model.savedID)
        #expect(model.contextChangedAfterSave)
        #expect(try await client.getQuestion(id: id).title == draft.title)
        #expect(await model.save(client: client, isCurrent: { true }) == nil)
        let other = ScreenClient.mock(key: "authoring-other-" + UUID().uuidString)
        #expect(await model.save(client: other, isCurrent: { true }) == nil)
    }

    @Test @MainActor
    func `project upload references stay scoped to create type and account and invalid uploads retain the draft`(
    ) async throws {
        let client = ScreenClient.mock(key: "authoring-upload-" + UUID().uuidString)
        let identity = ScreenBankIdentity(accountID: UUID(), clientIdentity: client.taskIdentity)
        let model = ScreenQuestionAuthoringModel()
        await model.prepare(questionID: nil, client: client, identity: identity)
        model.changeType(.project)
        model.draft.title = ["en": "Uploaded project"]
        let gzip = Data([0x1F, 0x8B, 0x08, 0, 0, 0, 0, 0, 0, 3])
        await model.upload(Data("wrong".utf8), filename: "bad.gz", client: client, isCurrent: { true })
        #expect(model.error != nil)
        #expect(model.draft.projectDetails == nil)
        await model.upload(gzip, filename: "project.tar.gz", client: client, isCurrent: { true })
        #expect(model.error == nil)
        #expect(model.draft.projectDetails?.temporaryFileID != nil)
        #expect(model.uploadFilename == "project.tar.gz")
        let id = try #require(await model.save(client: client, isCurrent: { true }))
        let editor = ScreenQuestionAuthoringModel()
        await editor.prepare(questionID: id, client: client, identity: identity)
        #expect(editor.draft.projectDetails?.temporaryFileID == nil)
        await editor.upload(gzip, filename: "second.tar.gz", client: client, isCurrent: { true })
        #expect(editor.uploadFilename == nil)
        let second = ScreenQuestionAuthoringModel()
        await second.prepare(questionID: nil, client: client, identity: identity)
        second.changeType(.project)
        var checks = 0
        await second.upload(
            gzip,
            filename: "retired.tar.gz",
            client: client,
            isCurrent: { checks += 1; return checks == 1 }
        )
        #expect(second.draft.projectDetails == nil)
        second.draft.projectDetails = ScreenProjectInput(temporaryFileID: "unscoped")
        #expect(await second.save(client: client, isCurrent: { true }) == nil)
        #expect(second.error != nil)
        second.changeType(.text)
        #expect(second.draft.projectDetails == nil)
    }

    @Test @MainActor
    func `cancelled operations and unauthorized clients cannot publish a question`() async {
        let client = ScreenClient.mock(unauthorized: true)
        let model = ScreenQuestionAuthoringModel()
        await model.prepare(
            questionID: nil,
            client: client,
            identity: ScreenBankIdentity(accountID: UUID(), clientIdentity: client.taskIdentity)
        )
        #expect(await model.save(client: client, isCurrent: { true }) == nil)
        #expect(model.error != nil)
        #expect(model.savedID == nil)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await model.save(client: client, isCurrent: { true })
        }
        #expect(await cancelled.value == nil)
    }

    @Test
    func `archive file loading rejects non gzip and oversized files without extracting them`() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("project.tar.gz")
        let gzip = Data([0x1F, 0x8B, 0x08, 0, 0, 0, 0, 0, 0, 3])
        try gzip.write(to: file)
        #expect(try ScreenProjectArchiveInput.read(file) == gzip)
        try Data("not gzip".utf8).write(to: file)
        #expect(throws: (any Error).self) { try ScreenProjectArchiveInput.read(file) }
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: UInt64(ScreenClient.maximumTemporaryFileBytes + 1))
        try handle.close()
        #expect(throws: (any Error).self) { try ScreenProjectArchiveInput.read(file) }
        #expect(throws: (any Error).self) { try ScreenProjectArchiveInput.read(directory) }
    }

    @Test @MainActor
    func `submission validation rejects invalid integers excessive body size and invalid choice indexes`() throws {
        var draft = ScreenQuestionSave(type: .mcq, points: -1)
        #expect(throws: (any Error).self) { try ScreenQuestionSubmission.validate(draft) }
        draft.points = Int(Int32.max) + 1
        #expect(throws: (any Error).self) { try ScreenQuestionSubmission.validate(draft) }
        draft.points = 0
        draft.mcqDetails = ScreenMCQInput(choices: [ScreenQuestionChoiceInput(label: ["en": "Choice"])])
        draft
            .evaluation =
            ScreenEvaluationInput(choiceSelection: ScreenChoiceSelectionInput(correctChoiceIndexes: [1]))
        #expect(throws: (any Error).self) { try ScreenQuestionSubmission.validate(draft) }
        draft.evaluation?.choiceSelection?.correctChoiceIndexes = [0]
        try ScreenQuestionSubmission.validate(draft)
        draft.statement = ["en": String(repeating: "x", count: 1024 * 1024)]
        #expect(throws: (any Error).self) { try ScreenQuestionSubmission.validate(draft) }
    }

    @Test @MainActor
    func `nested native input forms render for content evaluation and function schema`() {
        #expect(ImageRenderer(content: ScreenQuestionFields.fields(.constant(ScreenCodeInput(
            environment: ScreenEnvironmentInput(environmentID: "node"),
            functionSignature: ScreenFunctionSignatureInput(
                name: "solve",
                parameters: [["type": .string("integer")]],
                returnType: ["type": .string("integer")]
            )
        ))).frame(width: 600)).cgImage != nil)
        #expect(ImageRenderer(content: ScreenQuestionFields.fields(.constant(ScreenEvaluationInput(
            rubric: ScreenRubricInput(criteria: [ScreenRubricCriterionInput(
                label: ["en": "Correctness"],
                points: 0
            )]),
            inputOutput: ScreenInputOutputEvaluationInput(testCases: [ScreenInputOutputTestCaseInput(
                input: "1", output: "2", visibleToCandidate: false
            )])
        ))).frame(width: 600)).cgImage != nil)
    }
}
