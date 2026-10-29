import Foundation
@testable import PadBuddy
import Testing

@Suite("Unicode playback names")
struct PlaybackUnicodeNameTests {
    @Test(arguments: ["李雷", "Ольга", "Δημήτρης", "⁦李雷⁩"])
    func `safe names retain Unicode letters`(_ name: String) {
        #expect(PadPlaybackAuthors.displayName(name) == PadPlaybackAuthors.strippingInvisibles(name))
    }

    @Test(arguments: ["12345", "😀", "李雷@example.com", String(repeating: "李", count: 513)])
    func `unsafe or nonhuman values remain anonymous`(_ name: String) {
        #expect(PadPlaybackAuthors.displayName(name) == nil)
    }
}
