//
//  coderpadTests+CommandPaletteBuilder.swift
//  coderpadTests
//

@testable import CoderPad
import Foundation
import Testing

@Suite("Command palette builder")
struct CommandPaletteBuilderTests {
    @Test
    func `pad titles are trimmed and blank titles fall back to the id`() {
        #expect(CommandPaletteBuilder.padTitle(title: "  Interview  ", id: "pad-1") == "Interview")
        #expect(CommandPaletteBuilder.padTitle(title: " \n\t ", id: "pad-1") == "pad-1")
        #expect(CommandPaletteBuilder.padTitle(title: "", id: "pad-1") == "pad-1")
    }

    @Test
    func `new-pad candidates keep the first question for each id`() throws {
        func question(id: Int, title: String) throws -> Question {
            let data = try JSONSerialization.data(withJSONObject: ["id": id, "title": title])
            return try CoderPadClient.decoder.decode(Question.self, from: data)
        }

        let questions = try [
            question(id: 1, title: "First"),
            question(id: 1, title: "Duplicate"),
            question(id: 2, title: "Second")
        ]

        let unique = CommandPaletteBuilder.uniqueQuestions(questions)

        #expect(unique.map(\.id) == [1, 2])
        #expect(unique.map(\.title) == ["First", "Second"])
    }
}
