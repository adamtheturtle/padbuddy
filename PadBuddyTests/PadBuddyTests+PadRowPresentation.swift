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

    @Test func `the info block leaves the date announcement to the trailing date column`() throws {
        let dated = try decode(title: "Title", updatedAt: "2026-10-28T12:00:00Z")
        let undated = try decode(title: "Title")
        #expect(dated.informativeUpdatedAt != nil)
        #expect(PadRowPresentation(pad: dated, account: nil, owner: "Ada").accessibilityLabel
            == PadRowPresentation(pad: undated, account: nil, owner: "Ada").accessibilityLabel)
    }

    private func decode(title: String, updatedAt: String? = nil) throws -> Pad {
        var values = ["id": "pad-1", "title": title, "state": "started"]
        if let updatedAt {
            values["updated_at"] = updatedAt
        }
        let data = try JSONSerialization.data(withJSONObject: values)
        return try CoderPadClient.decoder.decode(Pad.self, from: data)
    }
}
