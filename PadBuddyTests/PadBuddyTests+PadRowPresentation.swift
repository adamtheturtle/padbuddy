import Foundation
@testable import PadBuddy
import Testing

@Suite("Pad row presentation")
struct PadRowPresentationTests {
    @Test func `title owner and account labels are bounded before layout and accessibility`() throws {
        let raw = "Remote\n\u{202E}" + String(repeating: "x", count: 10000)
        let pad = try decode(title: raw)
        let account = RowAccount(Account(name: raw, apiKey: ""))
        let presentation = PadRowPresentation(pad: pad, account: account, owner: raw)
        #expect(presentation.title.unicodeScalars.count <= 200)
        #expect(presentation.owner.unicodeScalars.count <= 120)
        #expect(account.name.unicodeScalars.count <= 80)
        #expect(presentation.accessibilityLabel.unicodeScalars.count < 600)
        #expect(!presentation.accessibilityLabel.contains("\u{202E}"))
        #expect(!presentation.accessibilityLabel.contains("\n"))
    }

    @Test func `unusable titles fall back to the pad identity`() throws {
        #expect(try decode(title: " \n\u{202E}").displayListTitle == "pad-1")
    }

    @Test func `different oversized tails do not affect row presentation equality`() throws {
        let first = try decode(title: String(repeating: "x", count: 200) + "one")
        let second = try decode(title: String(repeating: "x", count: 200) + "two")
        #expect(PadRowPresentation(pad: first, account: nil, owner: "Ada")
            == PadRowPresentation(pad: second, account: nil, owner: "Ada"))
    }

    private func decode(title: String) throws -> Pad {
        let data = try JSONSerialization.data(withJSONObject: ["id": "pad-1", "title": title, "state": "started"])
        return try JSONDecoder().decode(Pad.self, from: data)
    }
}
