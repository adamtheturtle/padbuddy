//
//  PadBuddyTests+QuestionDecoder.swift
//  PadBuddyTests
//

@testable import PadBuddy
import Foundation
import Testing

@Suite("Question decoder")
struct QuestionDecoderTests {
    private func decode(_ json: String) throws -> Question {
        try CoderPadClient.decoder.decode(Question.self, from: Data(json.utf8))
    }

    @Test
    func `decodes a full question`() throws {
        let json = """
        {
          "id": 42,
          "title": "Date Picker",
          "owner_email": "a@x.co",
          "language": "python3",
          "description": "desc",
          "candidate_instructions": [{"instructions": "go!", "default_visible": true}],
          "shared": true,
          "used": 12,
          "take_home": false,
          "test_cases_enabled": true,
          "solution": "sol",
          "pad_type": "live",
          "is_draft": false,
          "author_name": "Adam",
          "organization_name": "Cursor",
          "created_at": "2025-08-25T16:03:44Z",
          "updated_at": "2026-05-22T06:38:19Z"
        }
        """
        let question = try decode(json)
        #expect(question.id == 42)
        #expect(question.title == "Date Picker")
        #expect(question.ownerEmail == "a@x.co")
        #expect(question.language == "python3")
        #expect(question.used == 12)
        #expect(question.candidateInstructions.count == 1)
        #expect(question.candidateInstructions.first?.instructions == "go!")
        #expect(question.authorName == "Adam")
    }

    @Test
    func `decodes a minimal question with id only`() throws {
        let question = try decode(#"{"id": 1}"#)
        #expect(question.id == 1)
        #expect(question.title.isEmpty)
        #expect(question.ownerEmail.isEmpty)
        #expect(question.candidateInstructions.isEmpty)
    }

    @Test
    func `tolerates null fields throughout`() throws {
        let json = """
        {
          "id": 2,
          "title": null,
          "owner_email": null,
          "language": null,
          "description": null,
          "candidate_instructions": null,
          "shared": null,
          "used": null,
          "take_home": null,
          "test_cases_enabled": null,
          "solution": null,
          "pad_type": null,
          "is_draft": null,
          "author_name": null,
          "organization_name": null,
          "created_at": null,
          "updated_at": null
        }
        """
        let question = try decode(json)
        #expect(question.id == 2)
        #expect(question.candidateInstructions.isEmpty)
        #expect(question.publicTakeHomeSettingID == nil)
    }

    @Test
    func `decodes public_take_home_setting_id when present`() throws {
        let withSetting = try decode(#"{"id": 9, "public_take_home_setting_id": 7421}"#)
        #expect(withSetting.publicTakeHomeSettingID == 7421)

        // Absent in most questions (only take-home questions with a configured
        // public link carry it), so it must decode to nil rather than fail.
        let withoutSetting = try decode(#"{"id": 9}"#)
        #expect(withoutSetting.publicTakeHomeSettingID == nil)
    }

    @Test
    func `decodes test cases, mapping return_value and visibility`() throws {
        let json = """
        {
          "id": 7,
          "test_cases_enabled": true,
          "test_cases": [
            {"id": 1, "arguments": ["3"], "return_value": "Fizz", "visible": true},
            {"id": 2, "arguments": ["15"], "return_value": "FizzBuzz", "visible": false}
          ]
        }
        """
        let question = try decode(json)
        #expect(question.testCases.count == 2)
        #expect(question.testCases.first?.arguments == ["3"])
        #expect(question.testCases.first?.returnValue == "Fizz")
        #expect(question.testCases.first?.visible == true)
        #expect(question.testCases.last?.visible == false)
    }

    @Test
    func `defaults test cases to empty when the field is absent`() throws {
        let question = try decode(#"{"id": 8}"#)
        #expect(question.testCases.isEmpty)
    }

    @Test
    func `decodes custom file metadata`() throws {
        let json = """
        {
          "id": 9,
          "custom_files": [
            {"id": "cf1", "title": "Starter", "description": "Boilerplate",
             "filename": "main.py", "filesize": "1.2 KB"}
          ]
        }
        """
        let question = try decode(json)
        #expect(question.customFiles.count == 1)
        #expect(question.customFiles.first?.filename == "main.py")
        #expect(question.customFiles.first?.filesize == "1.2 KB")
        #expect(question.customFiles.first?.title == "Starter")
    }

    @Test
    func `defaults custom files to empty when the field is absent`() throws {
        let question = try decode(#"{"id": 10}"#)
        #expect(question.customFiles.isEmpty)
    }

    @Test @MainActor
    func `project question omitted by REST is presented as unavailable`() throws {
        let question = try decode("""
        {
          "id": 369025,
          "title": "Literalizer Debugging",
          "contents": null,
          "contents_for_test_cases": null,
          "language": null,
          "custom_files": []
        }
        """)
        let view = QuestionDetailView(
            client: CoderPadClient.mock(key: "project-question-api-gap"),
            question: question
        )

        #expect(!view.hasStarterCode)
        #expect(!view.hasMaterials)
        // The empty Materials branch renders `starterCodeUnavailableView`, not the
        // old authoritative "No code, tests, or files" state.
        _ = view.starterCodeUnavailableView
    }
}
