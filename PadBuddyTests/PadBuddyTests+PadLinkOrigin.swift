import Foundation
@testable import PadBuddy
import Testing

@Suite("Account-scoped pad link origin")
struct PadLinkOriginTests {
    @Test(arguments: [
        "https://other.example/P1", "https://pads.example:444/P1", "https://pads.example/settings",
        "https://user:secret@pads.example/P1", "http://pads.example/P1"
    ])
    func `unrelated API links fall back to the owning account pad route`(_ raw: String) throws {
        let json = try JSONSerialization.data(withJSONObject: ["id": "P1", "url": raw])
        let pad = try CoderPadClient.decoder.decode(Pad.self, from: json)
        let base = try #require(URL(string: "https://pads.example"))
        #expect(pad.webURL(fallbackBase: base)?.absoluteString == "https://pads.example/P1")
    }

    @Test func `equivalent origin and canonical pad path preserve useful URL components`() throws {
        let data = Data(#"{"id":"P1","url":"https://pads.example:443/P1?view=code#main"}"#.utf8)
        let pad = try CoderPadClient.decoder.decode(Pad.self, from: data)
        let base = try #require(URL(string: "https://pads.example"))
        #expect(pad.webURL(fallbackBase: base) == pad.webURL)
    }
}
