//
//  coderpadTests+CommandPaletteBuilder.swift
//  coderpadTests
//

@testable import CoderPad
import Testing

@Suite("Command palette builder")
struct CommandPaletteBuilderTests {
    @Test
    func `pad titles are trimmed and blank titles fall back to the id`() {
        #expect(CommandPaletteBuilder.padTitle(title: "  Interview  ", id: "pad-1") == "Interview")
        #expect(CommandPaletteBuilder.padTitle(title: " \n\t ", id: "pad-1") == "pad-1")
        #expect(CommandPaletteBuilder.padTitle(title: "", id: "pad-1") == "pad-1")
    }
}
