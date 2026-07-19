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
    func `account search text excludes email identity`() {
        let account = Account(name: "Production", apiKey: "key", userEmail: "sensitive@example.com")

        #expect(CommandPaletteBuilder.accountSearchText(account) == "Production")
    }

    @Test
    func `account candidates keep the first record for each id`() {
        let id = UUID()
        let first = Account(name: "First", apiKey: "key", id: id, userEmail: "first@example.com")
        let duplicate = Account(name: "Duplicate", apiKey: "key", id: id, userEmail: "second@example.com")
        let second = Account(name: "Second", apiKey: "key", id: UUID(), userEmail: "third@example.com")

        let unique = CommandPaletteBuilder.uniqueAccounts([first, duplicate, second])

        #expect(unique.map(\.id) == [first.id, second.id])
        #expect(unique.map(\.name) == ["First", "Second"])
    }

    @Test
    func `pad titles are trimmed and blank titles fall back to the id`() {
        #expect(CommandPaletteBuilder.padTitle(title: "  Interview  ", id: "pad-1") == "Interview")
        #expect(CommandPaletteBuilder.padTitle(title: " \n\t ", id: "pad-1") == "pad-1")
        #expect(CommandPaletteBuilder.padTitle(title: "", id: "pad-1") == "pad-1")
    }

    @Test
    func `pad candidates keep the first record for each id`() throws {
        func pad(id: String, title: String) throws -> Pad {
            let data = try JSONSerialization.data(withJSONObject: ["id": id, "title": title])
            return try CoderPadClient.decoder.decode(Pad.self, from: data)
        }

        let pads = try [
            pad(id: "pad-1", title: "First"),
            pad(id: "pad-1", title: "Duplicate"),
            pad(id: "pad-2", title: "Second")
        ]

        let unique = CommandPaletteBuilder.uniquePads(pads)

        #expect(unique.map(\.id) == ["pad-1", "pad-2"])
        #expect(unique.map(\.title) == ["First", "Second"])
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
