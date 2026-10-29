import Foundation
@testable import PadBuddy
import Testing

@Suite("Dock badge owner identity bounds")
struct DockBadgeIdentityTests {
    @Test func `oversized and empty ownership identities are not compared`() {
        #expect(DockBadgeController.canonicalBadgeEmail(String(repeating: "x", count: 1_000_000)) == nil)
        #expect(DockBadgeController.canonicalBadgeEmail(" \n ") == nil)
        #expect(DockBadgeController.canonicalBadgeEmail(String(repeating: "x", count: 255)) == nil)
        #expect(DockBadgeController.canonicalBadgeEmail("person@coderpad.io") == "person@coderpad.io")
    }

    @Test func `badge counting rejects unsafe IDs before retaining them and preserves first record semantics`() throws {
        func pad(_ id: String, state: String = "started", owner: String = "ada@example.com") throws -> Pad {
            let data = try JSONSerialization.data(withJSONObject: [
                "id": id, "state": state, "owner_email": owner
            ])
            return try CoderPadClient.decoder.decode(Pad.self, from: data)
        }
        let pads = try [
            pad("P1"), pad("P1"), pad("P2", state: "ended"), pad("P2"),
            pad("P3", owner: "other@example.com"), pad("P4", owner: "ADA@example.com"),
            pad(String(repeating: "x", count: 10000)), pad("unsafe.id")
        ]
        #expect(DockBadgeController.ownActivePadCount(pads, ownerEmail: "ada@example.com") == 2)
    }
}
