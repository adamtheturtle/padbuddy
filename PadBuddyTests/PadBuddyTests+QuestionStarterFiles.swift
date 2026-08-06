@testable import PadBuddy
import Foundation
import Testing

@Suite("Question starter-file mutations")
struct QuestionStarterFileTests {
    @Test func `multi-file create preserves ordered paths empty files and Unicode`() throws {
        let body = NewQuestionSheet.normalizedCreateBody(NewQuestionSheet.CreateDraft(
            title: "Project", language: "multifile_python3", description: "", instructions: "",
            solution: "", padType: "live", fileContents: [
                QuestionStarterFileDraft(path: "src/世界.py", contents: "print('你好')\n"),
                QuestionStarterFileDraft(path: "tests/__init__.py", contents: "")
            ]
        ))
        let files = try #require(body.fileContents)

        #expect(files.map(\.path) == ["src/世界.py", "tests/__init__.py"])
        #expect(files.map(\.contents) == ["print('你好')\n", ""])
        #expect(body.contents == nil)
    }

    @Test func `single-file create excludes hidden project drafts`() {
        let body = NewQuestionSheet.normalizedCreateBody(NewQuestionSheet.CreateDraft(
            title: "Single", language: "python3", description: "", instructions: "",
            solution: "", padType: "live",
            fileContents: [QuestionStarterFileDraft(path: "main.py", contents: "print(1)")]
        ))

        #expect(body.fileContents == nil)
    }

    @Test func `SDK rejects conflicting question content sources`() {
        let body = QuestionCreate(
            title: "Conflict",
            contents: "single",
            fileContents: [QuestionFileContent(path: "main.py", contents: "project")]
        )

        #expect(throws: QuestionMutationValidationError.self) {
            _ = try JSONEncoder().encode(body)
        }
    }

    @Test func `replacement request preserves structured starter files`() throws {
        let body = QuestionUpdate(id: 42, fileContents: [
            QuestionFileContent(path: "src/é.swift", contents: "print(\"世界\")"),
            QuestionFileContent(path: "empty.txt", contents: "")
        ])
        let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any])
        let question = try #require(object["question"] as? [String: Any])
        let files = try #require(question["file_contents"] as? [[String: String]])

        #expect(files.map { $0["path"] } == ["src/é.swift", "empty.txt"])
        #expect(files.map { $0["contents"] } == ["print(\"世界\")", ""])
        #expect(object["contents"] == nil)
    }

    @Test func `creation drafts restore structured starter files`() throws {
        let original = QuestionCreationDraft(
            title: "Project", language: "multifile_python3", description: "", instructions: "",
            solution: "", padType: "live", draftPrompt: "", selectedSection: "instructions",
            starterFiles: [QuestionStarterFileDraft(path: "src/main.py", contents: "print('✓')")]
        )

        let restored = try JSONDecoder().decode(
            QuestionCreationDraft.self,
            from: JSONEncoder().encode(original)
        )
        #expect(restored.starterFiles == original.starterFiles)
    }

    @Test func `ZIP selections preserve Unicode filenames and zero-byte data`() {
        let selection = QuestionZIPSelection(data: Data(), filename: "proyecto-世界.zip")

        #expect(selection.upload.filename == "proyecto-世界.zip")
        #expect(selection.upload.data.isEmpty)
    }

    @Test func `SDK rejects a ZIP combined with structured starter files`() async {
        let client = CoderPadClient.mock(key: "zip-conflict-\(UUID().uuidString)")
        let body = QuestionCreate(
            title: "Conflict",
            fileContents: [QuestionFileContent(path: "main.py", contents: "")]
        )

        await #expect(throws: QuestionMutationValidationError.self) {
            _ = try await client.createQuestion(
                body,
                zipFile: QuestionZIPUpload(data: Data(), filename: "empty.zip")
            )
        }
    }

    @Test func `starter paths must be present and unique without changing valid paths`() {
        #expect([QuestionStarterFileDraft(path: "src/main.py", contents: "")].hasInvalidStarterFilePaths == false)
        #expect([QuestionStarterFileDraft(path: " ", contents: "")].hasInvalidStarterFilePaths)
        #expect([
            QuestionStarterFileDraft(path: "main.py", contents: "one"),
            QuestionStarterFileDraft(path: "main.py", contents: "two")
        ].hasInvalidStarterFilePaths)
    }
}
