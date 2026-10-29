import Foundation
@testable import PadBuddy
import Testing

@Suite("Pad mutation confirmation identity")
@MainActor
struct PadMutationTargetTests {
    @Test func `confirmation cannot move to another account pad or credential generation`() {
        let id = UUID()
        let original = Account(name: "Original", apiKey: "old", id: id)
        let replacement = Account(name: "Replacement", apiKey: "new", id: id)
        let target = PadMutationTarget(pad: Pad(id: "ABC123", title: "Original"),
                                       client: original.makeClient(), accountID: id)
        #expect(target.resolve(padID: "ABC123", client: original.makeClient(), accounts: [original])?.id == id)
        #expect(target.resolve(padID: "ABC123", client: original.makeClient(), accounts: []) == nil)
        #expect(target.resolve(padID: "ABC123", client: original.makeClient(), accounts: [replacement]) == nil)
        #expect(target.resolve(padID: "ABC123", client: replacement.makeClient(), accounts: [replacement]) == nil)
        #expect(target.resolve(padID: "XYZ789", client: original.makeClient(), accounts: [original]) == nil)
    }
}
