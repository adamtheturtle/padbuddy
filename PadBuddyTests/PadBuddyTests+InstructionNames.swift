import Foundation
@testable import PadBuddy
import Testing

@Suite("Instruction step names")
struct InstructionNameTests {
    @Test
    func `named and unnamed steps retain their distinct display labels`() throws {
        let values = try instructions()
        #expect(QuestionInstructionNames.title(values[0], index: 0) == "Introduction")
        #expect(QuestionInstructionNames.title(values[1], index: 1) == String(localized: "Part 2"))
        #expect(QuestionInstructionNames.normalized("  Name\nwith tabs\t  ") == "Name with tabs")
        #expect(QuestionInstructionNames.normalized(" \n ") == nil)
        let bounded = QuestionInstructionNames.normalized(String(repeating: "a", count: 300))
        #expect(bounded == String(repeating: "a", count: 200))
    }

    @Test
    func `renaming and clearing one step preserve instructions other names and visibility`() throws {
        let values = try instructions()
        let edit = nameEdit(values[1], index: 1)
        let renamed = try #require(QuestionInstructionNames.renamed(values, edit: edit, name: " Follow-up "))
        #expect(renamed.map(\.name) == ["Introduction", "Follow-up"])
        #expect(renamed.map(\.instructions) == ["First **Markdown**", "Second"])
        #expect(renamed.map(\.defaultVisible) == [true, false])
        let firstEdit = nameEdit(values[0], index: 0)
        let cleared = try #require(QuestionInstructionNames.renamed(values, edit: firstEdit, name: ""))
        #expect(cleared.map(\.name) == [nil, nil])
    }

    @Test
    func `a moved step is resolved uniquely and concurrent changes are rejected`() throws {
        let values = try instructions()
        let edit = nameEdit(values[0], index: 0)
        let reversed = Array(values.reversed())
        let moved = try #require(QuestionInstructionNames.renamed(reversed, edit: edit, name: "Renamed"))
        #expect(moved.map(\.name) == [nil, "Renamed"])
        #expect(QuestionInstructionNames.renamed([values[1]], edit: edit, name: "Renamed") == nil)
        let changed = try JSONDecoder().decode(CandidateInstruction.self, from: Data(
            #"{"instructions":"First **Markdown**","name":"Changed elsewhere","default_visible":true}"#.utf8
        ))
        #expect(QuestionInstructionNames.renamed([changed, values[1]], edit: edit, name: "Renamed") == nil)
        let ambiguous = nameEdit(values[0], index: 5)
        #expect(QuestionInstructionNames.renamed([values[0], values[0]], edit: ambiguous, name: "Renamed") == nil)
    }

    @Test
    func `create update and optimistic round trips preserve named and hidden steps`() async throws {
        let client = CoderPadClient.mock(key: "instruction-name-roundtrip-" + UUID().uuidString)
        let body = NewQuestionSheet.normalizedCreateBody(NewQuestionSheet.CreateDraft(
            title: "Names", language: "python3", description: "", instructions: "First **Markdown**",
            solution: "", padType: "live", instructionName: " Introduction "
        ))
        let created = try await client.createQuestion(body)
        #expect(created.candidateInstructions.map(\.name) == ["Introduction"])
        let payloads = try instructions().map {
            CandidateInstructionPayload(instructions: $0.instructions, defaultVisible: $0.defaultVisible, name: $0.name)
        }
        let update = QuestionUpdate(id: created.id, candidateInstructions: payloads)
        let saved = try await client.updateQuestion(update)
        #expect(saved.candidateInstructions.map(\.name) == ["Introduction", nil])
        #expect(saved.candidateInstructions.map(\.defaultVisible) == [true, false])
        let optimistic = created.applying(candidateInstructions: payloads)
        #expect(optimistic.candidateInstructions == saved.candidateInstructions)
    }

    @Test
    func `creation draft storage preserves names and accepts drafts without the new field`() throws {
        let data = Data("""
        {"title":"Draft","language":"python3","description":"","instructions":"Body",
         "solution":"","padType":"live","draftPrompt":"","selectedSection":"instructions"}
        """.utf8)
        var draft = try JSONDecoder().decode(QuestionCreationDraft.self, from: data)
        #expect(draft.instructionName == nil)
        draft.instructionName = "Draft step"
        let restored = try JSONDecoder().decode(QuestionCreationDraft.self, from: JSONEncoder().encode(draft))
        #expect(restored.instructionName == "Draft step")
        #expect(NewQuestionSheet.normalizedRestoredDraft(restored).instructionName == "Draft step")
    }

    private func instructions() throws -> [CandidateInstruction] {
        let data = Data("""
        [{"instructions":"First **Markdown**","name":"Introduction","default_visible":true},
         {"instructions":"Second","default_visible":false}]
        """.utf8)
        return try JSONDecoder().decode([CandidateInstruction].self, from: data)
    }

    private func nameEdit(_ instruction: CandidateInstruction, index: Int) -> InstructionNameEdit {
        let identity = ClientTaskIdentity(apiKey: "test-key", baseURL: CoderPadClient.defaultBaseURL)
        return InstructionNameEdit(index: index, instruction: instruction, questionID: 42, accountID: nil,
                                   clientIdentity: identity)
    }
}
