import Foundation
@testable import PadBuddy
import SwiftUI
import Testing

@MainActor
struct QuestionBinaryFilesTests {
    @Test
    func `solution edits preserve a project whose environment identifier is unavailable`() throws {
        let variant = try JSONDecoder().decode(QuestionVariant.self, from: Data(#"""
        {"id":7,"question_id":42,"language":null,"project_template_id":12,
        "file_contents":[{"path":"image.png","binary":true}]}
        """#.utf8))
        var draft = QuestionVariantDraft(variant: variant)
        draft.solution = "Changed solution"
        #expect(draft.canSave)
        #expect(draft.mutation.language == nil)
        #expect(draft.mutation.fileContents == nil)
        #expect(draft.mutation.solution == "Changed solution")
    }

    @Test(arguments: [true, false])
    func `unavailable original files permit solution edits but block code replacements`(binary: Bool) throws {
        let variant = try JSONDecoder().decode(QuestionVariant.self, from: Data("""
        {"id":7,"question_id":42,"language":null,"project_template_slug":"react",
        "file_contents":[{"path":"image.png","binary":\(binary)}]}
        """.utf8))
        var draft = QuestionVariantDraft(variant: variant)
        draft.solution = "Changed solution"
        #expect(draft.canSave)
        #expect(draft.mutation.fileContents == nil)
        #expect(draft.mutation.language == nil)
        #expect(draft.mutation.solution == "Changed solution")
        for source in [QuestionVariantDraft.CodeSource.projectFiles, .singleFile, .languageDefault] {
            draft.codeSource = source
            #expect(!draft.canSave)
        }
        draft.files = []
        #expect(!draft.canSave)
        draft.codeSource = .preserve
        draft.language = "python3"
        #expect(!draft.canSave)
        draft.language = "react"
        #expect(draft.canSave)
    }

    @Test
    func `parent binary entries prevent text replacement and retain metadata through title edits`() throws {
        let question = try JSONDecoder().decode(Question.self, from: Data(#"""
        {"id":42,"file_contents":[{"path":"image.png","binary":true}]}
        """#.utf8))
        #expect(question.hasBinaryStarterFiles)
        #expect(question.applying(title: "Renamed").fileContents == question.fileContents)
        let deleted = try JSONDecoder().decode(Question.self, from: Data(#"""
        {"id":42,"file_contents":[{"path":"image.png","binary":true,"deleted":true}]}
        """#.utf8))
        #expect(!deleted.hasBinaryStarterFiles)
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func `variant file previews render binary blank removed and unavailable files in read-only mode`(
        scheme: ColorScheme
    ) {
        let variants: [QuestionVariantFileContent] = [
            .init(path: "image.png", binary: true), .init(path: "blank.txt", contents: "", binary: false),
            .init(path: "removed.txt", deleted: true), .init(path: "unknown.py"),
            .init(path: "main.py", contents: "print(1)", hidden: true)
        ]
        let files = variants.map(\.starterFile)
        #expect(files[0].binary == true)
        #expect(files[2].deleted == true)
        for file in files {
            let renderer = ImageRenderer(content: QuestionProjectStarterFile(file: file, language: nil)
                .contents.frame(width: 340).environment(\.colorScheme, scheme).environment(\.isReadOnly, true))
            #expect((renderer.nsImage?.size.height ?? 0) > 0)
        }
        let renderer = ImageRenderer(content: QuestionProjectStarterFiles(files: files, language: "react")
            .frame(width: 340).environment(\.colorScheme, scheme).environment(\.isReadOnly, true))
        #expect((renderer.nsImage?.size.height ?? 0) > 0)
    }
}
