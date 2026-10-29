import Foundation
@testable import PadBuddy
import Testing

@Suite("Bounded event identities")
struct BoundedEventIdentityTests {
    @Test func `remote fields are bounded before composing event identities`() {
        let remote = String(repeating: "a\n", count: 1_000_000)
        let event = PadEvent(message: remote, kind: remote, userName: remote)
        #expect(event.identity.count <= 4 * 64 + 3)
        #expect(!event.identity.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains))
        #expect(PadEventGrouping.identitySuffix(for: event).count <= PadEventGrouping.maxIdentitySuffixLength)
    }
}
