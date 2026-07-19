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
    func `remote palette text is single-line and bounded`() {
        let value = "  Remote\n\tTitle\0  " + String(repeating: "x", count: 400)
        let normalized = CommandPaletteBuilder.sanitizedRemoteText(value)

        #expect(normalized.hasPrefix("Remote Title "))
        #expect(!normalized.contains("\n"))
        #expect(!normalized.contains("\t"))
        #expect(!normalized.contains("\0"))
        #expect(normalized.count == 160)
        #expect(CommandPaletteBuilder.sanitizedRemoteText(" \n ", fallback: "Fallback") == "Fallback")
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
    func `pad palette metadata contains no owner email`() throws {
        let sensitive = "candidate-owner-sensitive@example.com"
        let data = try JSONSerialization.data(withJSONObject: [
            "id": "pad-1", "title": "Backend interview", "owner_email": sensitive
        ])
        let pad = try CoderPadClient.decoder.decode(Pad.self, from: data)
        let text = CommandPaletteBuilder.padPaletteText(
            pad, account: "Production"
        )

        #expect(text.title == "Backend interview")
        #expect(text.subtitle == "Production")
        #expect(text.searchText == "Backend interview")
        #expect(!"\(text.title) \(text.subtitle ?? "") \(text.searchText)".contains(sensitive))
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
    func `pad candidate limit ignores duplicates and stops deterministically`() throws {
        func pad(id: String) throws -> Pad {
            let data = try JSONSerialization.data(withJSONObject: ["id": id, "title": id])
            return try CoderPadClient.decoder.decode(Pad.self, from: data)
        }

        let pads = try [pad(id: "one"), pad(id: "one"), pad(id: "two"), pad(id: "three")]
        let bounded = CommandPaletteBuilder.uniquePads(pads, limit: 2)

        #expect(bounded.map(\.id) == ["one", "two"])
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

    @Test
    func `question candidate limit ignores duplicates and stops deterministically`() throws {
        func question(id: Int) throws -> Question {
            let data = try JSONSerialization.data(withJSONObject: ["id": id, "title": "Question \(id)"])
            return try CoderPadClient.decoder.decode(Question.self, from: data)
        }

        let questions = try [question(id: 1), question(id: 1), question(id: 2), question(id: 3)]
        let bounded = CommandPaletteBuilder.uniqueQuestions(questions, limit: 2)

        #expect(bounded.map(\.id) == [1, 2])
        #expect(CommandPaletteBuilder.uniqueQuestions(questions, limit: 0).isEmpty)
    }
}
