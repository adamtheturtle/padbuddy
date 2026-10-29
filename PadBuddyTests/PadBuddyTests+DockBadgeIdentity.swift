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
}
