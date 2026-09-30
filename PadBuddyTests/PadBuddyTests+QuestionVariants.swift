import Foundation
@testable import PadBuddy
import Testing

@Suite("Question variant editing")
struct QuestionVariantEditingTests {
    @Test
    func `new variants require an environment and preserve default code`() {
        var draft = QuestionVariantDraft()
        #expect(draft.mutation.language == "ruby")
        #expect(draft.mutation.contents == .unchanged)
        #expect(draft.mutation.fileContents == nil)
        draft.language = "  "
        #expect(!draft.canSave)
        draft.language = "react"
        draft.codeSource = .projectFiles
        #expect(draft.mutation.fileContents?.isEmpty == true)
    }

    @Test
    func `solution edits omit code and unchanged environment`() throws {
        var draft = try QuestionVariantDraft(variant: variant())
        draft.solution = "new solution"
        #expect(draft.mutation.language == nil)
        #expect(draft.mutation.contents == .unchanged)
        #expect(draft.mutation.solution == "new solution")
        #expect(draft.mutation.fileContents == nil)
    }

    @Test
    func `blank and default code are separate explicit mutations`() throws {
        var draft = try QuestionVariantDraft(variant: variant())
        draft.codeSource = .singleFile
        draft.contents = ""
        #expect(draft.mutation.contents == .value(""))
        draft.codeSource = .languageDefault
        #expect(draft.mutation.contents == .languageDefault)
        draft.language = "python3"
        #expect(draft.mutation.language == "python3")
    }

    @Test
    func `project edits retain decoded paths and hidden flags and permit a template reset`() throws {
        var draft = try QuestionVariantDraft(variant: variant(template: true))
        #expect(draft.isProjectTemplate)
        #expect(draft.language == "react")
        #expect(draft.mutation.language == nil)
        draft.codeSource = .projectFiles
        #expect(draft.files.map(\.file.path) == [".cpad", "hello world.jsx"])
        #expect(draft.mutation.fileContents?.last?.hidden == true)
        draft.files = []
        #expect(draft.mutation.fileContents?.isEmpty == true)
        #expect(draft.canSave)
    }

    @Test
    func `files reject duplicate paths traversal and cpad deletion`() {
        var draft = QuestionVariantDraft()
        draft.codeSource = .projectFiles
        draft.files = [.init(file: .init(path: "../bad", contents: ""))]
        #expect(!draft.canSave)
        draft.files = [.init(file: .init(path: "same", contents: "")),
                       .init(file: .init(path: "same", contents: ""))]
        #expect(!draft.canSave)
        draft.files = [.init(file: .init(path: ".cpad", contents: ""), deleted: true)]
        #expect(!draft.canSave)
    }

    private func variant(template: Bool = false) throws -> QuestionVariant {
        let object: [String: Any] = [
            "id": 7, "question_id": 42, "language": template ? "javascript" : "ruby",
            "project_template_id": template ? 1 : NSNull(),
            "project_template_slug": template ? "react" : NSNull(),
            "display": "Ruby", "contents": "puts 1", "solution": "puts 2",
            "file_contents": template ? [["path": ".cpad", "contents": "{}"],
                                         ["path": "hello world.jsx", "contents": "hello", "hidden": true]] : NSNull()
        ]
        return try JSONDecoder().decode(QuestionVariant.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
