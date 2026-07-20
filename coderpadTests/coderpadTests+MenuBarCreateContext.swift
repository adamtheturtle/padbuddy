//
//  coderpadTests+MenuBarCreateContext.swift
//  coderpadTests
//

@testable import CoderPad
import Testing

@Suite("Menu bar create context")
struct MenuBarCreateContextTests {
    @Test @MainActor
    func `menu bar create context rejects removed and rekeyed accounts`() {
        let original = Account(name: "Original", apiKey: "first")
        let context = MenuBarCreateContext(account: original)
        var renamed = original
        renamed.name = "Renamed"
        var rekeyed = original
        rekeyed.apiKey = "second"

        #expect(context.resolve(in: [original])?.id == original.id)
        #expect(context.resolve(in: [renamed])?.name == "Renamed")
        #expect(context.resolve(in: [rekeyed]) == nil)
        #expect(context.resolve(in: []) == nil)
    }
}
