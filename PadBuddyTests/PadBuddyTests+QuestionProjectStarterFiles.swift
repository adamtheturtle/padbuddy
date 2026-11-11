@testable import PadBuddy
import SwiftUI
import Testing

@MainActor
struct QuestionProjectStarterFilesTests {
    @Test(arguments: ["null", "[]"])
    func `unmodified project templates remain available for catalogue lookup`(files: String) throws {
        let question = try CoderPadClient.decoder.decode(Question.self, from: Data("""
        {"id":1,"title":"Project","language":"multifile_python","contents":null,"file_contents":\(files)}
        """.utf8))
        let detail = QuestionDetailView(client: .mock(key: "unmodified-project"), question: question)
        #expect(detail.hasStarterCode)
        #expect(detail.hasMaterials)
    }

    @Test(arguments: [
        #"[{"path":"src/main.py","contents":"print(1)","hidden":true},{"path":"old.py","deleted":true}]"#,
        #"[{"path":"empty.py","contents":""}]"#,
        #"[{"path":"old.py","deleted":true}]"#
    ])
    func `project files make Materials available without single-file contents`(files: String) throws {
        let question = try decodeQuestion(files: files)
        let detail = QuestionDetailView(client: .mock(key: "project-starter-files"), question: question)
        #expect(question.contents == nil)
        #expect(detail.hasStarterCode)
        #expect(detail.hasMaterials)

        let renderer = ImageRenderer(content: detail.materialsPane.frame(width: 340))
        #expect((renderer.nsImage?.size.height ?? 0) > 0)
    }

    @Test(arguments: ["null", "[]"])
    func `absent project code still uses the unavailable state`(files: String) throws {
        let detail = try QuestionDetailView(client: .mock(key: "project-starter-files"),
                                            question: decodeQuestion(files: files))
        #expect(!detail.hasStarterCode)
        #expect(!detail.hasMaterials)
    }

    @Test(arguments: ["", "print(1)", nil] as [String?])
    func `expanded file contents render in both appearances`(contents: String?) throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "path": "src/main.py", "contents": contents as Any? ?? NSNull()
        ])
        let file = try JSONDecoder().decode(QuestionStarterFile.self, from: data)
        for scheme in [ColorScheme.light, .dark] {
            let renderer = ImageRenderer(content: QuestionProjectStarterFile(file: file, language: "multifile_python")
                .contents.frame(width: 340).environment(\.colorScheme, scheme))
            #expect((renderer.nsImage?.size.height ?? 0) > 0)
        }
    }

    private func decodeQuestion(files: String) throws -> Question {
        try CoderPadClient.decoder.decode(Question.self, from: Data("""
        {"id":1,"title":"Project","contents":null,"file_contents":\(files)}
        """.utf8))
    }
}
