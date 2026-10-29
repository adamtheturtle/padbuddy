import Foundation
@testable import PadBuddy
import Testing

@Suite("Question custom file presentation")
struct QuestionCustomFilePresentationTests {
    @Test func `file metadata is bounded before reaching rows`() throws {
        let raw = "Remote\n\u{202E}" + String(repeating: "x", count: 10000)
        let data = try JSONSerialization.data(withJSONObject: [
            "filename": raw, "title": raw, "description": raw, "filesize": raw
        ])
        let file = try JSONDecoder().decode(QuestionCustomFile.self, from: data)
        let presentation = QuestionCustomFilePresentation(file)
        #expect(presentation.name.unicodeScalars.count <= 256)
        #expect(presentation.description.unicodeScalars.count <= 512)
        #expect(presentation.size.unicodeScalars.count <= 40)
        #expect(!presentation.name.contains("\u{202E}"))
        #expect(!presentation.description.contains("\n"))
    }

    @Test func `unusable filenames fall back to safe titles`() throws {
        let data = Data(#"{"filename":" \n","title":"Friendly title"}"#.utf8)
        let file = try JSONDecoder().decode(QuestionCustomFile.self, from: data)
        #expect(QuestionCustomFilePresentation(file).name == "Friendly title")
    }
}
