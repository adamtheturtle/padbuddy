import Foundation
@testable import PadBuddy
import Testing

@Suite("Question instruction previews")
struct QuestionInstructionPreviewTests {
    @Test func `inline editing requires a bounded complete list without truncating saved parts`() throws {
        let ordinary = try instruction("Read this")
        #expect(QuestionInstructionPreview.canEdit(Array(repeating: ordinary, count: 16)))
        #expect(!QuestionInstructionPreview.canEdit(Array(repeating: ordinary, count: 17)))
        let large = try instruction(String(repeating: "x", count: 16385))
        #expect(!QuestionInstructionPreview.canEdit([ordinary, large]))
        let largeName = try instruction("Read this", name: String(repeating: "x", count: 201))
        #expect(!QuestionInstructionPreview.canEdit([largeName]))
        #expect(QuestionInstructionPreview.canEdit([]))
    }

    @Test func `instruction headings use bounded control free names`() throws {
        let item = try instruction("Read this", name: "Step\n\u{202E}" + String(repeating: "x", count: 10000))
        let title = QuestionInstructionNames.title(item, index: 0)
        #expect(title.unicodeScalars.count <= 200)
        #expect(!title.contains("\u{202E}"))
        #expect(!title.contains("\n"))
    }

    private func instruction(_ text: String, name: String = "Step") throws -> CandidateInstruction {
        let data = try JSONSerialization.data(withJSONObject: [
            "instructions": text, "name": name, "default_visible": true
        ])
        return try JSONDecoder().decode(CandidateInstruction.self, from: data)
    }
}
