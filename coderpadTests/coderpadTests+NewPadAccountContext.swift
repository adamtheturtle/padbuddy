//
//  coderpadTests+NewPadAccountContext.swift
//  coderpadTests
//

@testable import CoderPad
import Testing

extension coderpadTests {
    @Test @MainActor
    func `new pad context rejects removed and rekeyed target accounts`() {
        let original = Account(name: "Original", apiKey: "first")
        let context = NewPadAccountContext(client: original.makeClient(), targetAccountID: original.id)
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
