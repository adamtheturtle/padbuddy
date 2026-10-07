import Foundation
@testable import PadBuddy
import SwiftUI
import Testing

@Suite("Question sharing and database associations")
struct QuestionAssociationTests {
    @Test
    func `untouched settings omit fields while false and integer IDs remain explicit`() throws {
        let data = try JSONEncoder().encode(QuestionAssociationDraft().update(questionID: 101))
        let untouched = try JSONDecoder().decode([String: JSONValue].self, from: data)
        #expect(untouched.isEmpty)
        let draft = QuestionAssociationDraft(shared: false, databaseID: " 501 ")
        let encoded = try JSONEncoder().encode(draft.update(questionID: 101))
        #expect(try JSONDecoder().decode([String: JSONValue].self, from: encoded) == [
            "shared": .bool(false), "custom_database_id": .number(501)
        ])
        let create = draft.applying(to: QuestionCreate(title: "Unchanged title"))
        #expect(create.shared == false)
        #expect(create.customDatabaseID == 501)
        #expect(create.title == "Unchanged title")
    }

    @Test
    func `database identity requires a positive integer and accepts an empty default`() {
        for value in ["0", "-1", "1.5", "2147483648", "database"] {
            #expect(QuestionAssociationDraft(databaseID: value).validationMessage != nil)
        }
        for value in ["", " ", "1", "501", "2147483647"] {
            #expect(QuestionAssociationDraft(databaseID: value).validationMessage == nil)
        }
        #expect(QuestionAssociationDraft().isMeaningful == false)
        #expect(QuestionAssociationDraft(shared: false).isMeaningful == true)
    }

    @Test @MainActor
    func `creation and saves preserve unrelated content and omitted associations`() async throws {
        let client = CoderPadClient.mock(key: "associations-" + UUID().uuidString)
        let created = try await client.createQuestion(QuestionAssociationDraft(shared: false, databaseID: "501")
            .applying(to: QuestionCreate(title: "Database", language: "postgresql", description: "Keep this")))
        #expect(created.shared == false)
        #expect(created.customDatabase?.id == 501)
        let model = QuestionAssociationModel()
        let saved = await model.save(QuestionAssociationDraft(shared: true), questionID: created.id,
                                     client: client, isCurrent: { true })
        #expect(saved?.shared == true)
        #expect(saved?.customDatabase?.id == 501)
        #expect(saved?.description == "Keep this")
        #expect(saved?.title == "Database")
        #expect(model.error == nil)
        #expect(model.saving == false)
    }

    @Test @MainActor
    func `author permissions and unknown database failures preserve the server and draft`() async throws {
        let client = CoderPadClient.mock(key: "association-errors-" + UUID().uuidString)
        let before = try await client.getQuestion(id: 101)
        let model = QuestionAssociationModel()
        let forbidden = await model.save(QuestionAssociationDraft(shared: false), questionID: before.id,
                                         client: client, isCurrent: { true })
        #expect(forbidden == nil)
        #expect(model.error != nil)
        let after = try await client.getQuestion(id: 101)
        #expect(after.shared == before.shared)
        let draft = QuestionAssociationDraft(databaseID: "999")
        let invalid = await model.save(draft, questionID: before.id, client: client, isCurrent: { true })
        #expect(invalid == nil)
        #expect(model.error != nil)
        #expect(draft.databaseID == "999")
        let unchanged = try await client.getQuestion(id: 101)
        #expect(unchanged.customDatabase == before.customDatabase)
    }

    @Test @MainActor
    func `changed identity rejects a save and cancellation publishes no result`() async throws {
        let client = CoderPadClient.mock(key: "association-identity-" + UUID().uuidString)
        let created = try await client.createQuestion(QuestionCreate(title: "Identity", shared: true))
        let model = QuestionAssociationModel()
        let draft = QuestionAssociationDraft(shared: false)
        let stale = await model.save(draft, questionID: created.id, client: client, isCurrent: { false })
        #expect(stale == nil)
        #expect(model.error != nil)
        let after = try await client.getQuestion(id: created.id)
        #expect(after.shared == true)
        var checks = 0
        let retired = await model.save(draft, questionID: created.id, client: client, isCurrent: {
            checks += 1
            return checks == 1
        })
        #expect(retired == nil)
        #expect(checks == 2)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await model.save(draft, questionID: created.id, client: client, isCurrent: { true })
        }
        let cancelled = await task.value
        #expect(cancelled == nil)
        #expect(model.error == nil)
    }

    @Test
    func `creation restoration retains options and accepts earlier drafts`() throws {
        let data = Data("""
        {"title":"Draft","language":"python3","description":"","instructions":"","solution":"",
         "padType":"live","draftPrompt":"","selectedSection":"instructions"}
        """.utf8)
        var draft = try JSONDecoder().decode(QuestionCreationDraft.self, from: data)
        #expect(draft.association == nil)
        draft.association = QuestionAssociationDraft(shared: false, databaseID: "501")
        let restored = NewQuestionSheet.normalizedRestoredDraft(draft)
        #expect(restored.association == draft.association)
        let decoded = try JSONDecoder().decode(QuestionCreationDraft.self, from: JSONEncoder().encode(restored))
        #expect(decoded == restored)
    }

    @Test @MainActor
    func `association editor renders current metadata and default choices`() async throws {
        let client = CoderPadClient.mock()
        let question = try await client.getQuestion(id: 101)
        let renderer = ImageRenderer(content: QuestionAssociationEditor(
            client: client, question: question, isCurrent: { true }, onSaved: { _ in }
        ).frame(width: 520, height: 500))
        #expect(renderer.cgImage != nil)
    }
}
