import Foundation
@testable import PadBuddy
import Testing

@Suite("Account-scoped pad link origin")
struct PadLinkOriginTests {
    @Test(arguments: [
        "https://coderpad.io/P1", "https://app.coderpad.io:444/P1", "https://app.coderpad.io/settings",
        "https://user:secret@app.coderpad.io/P1", "http://app.coderpad.io/P1"
    ])
    func `unrelated API links fall back to the owning account pad route`(_ raw: String) throws {
        let json = try JSONSerialization.data(withJSONObject: ["id": "P1", "url": raw])
        let pad = try CoderPadClient.decoder.decode(Pad.self, from: json)
        let base = try #require(URL(string: "https://app.coderpad.io"))
        #expect(pad.webURL(fallbackBase: base)?.absoluteString == "https://app.coderpad.io/P1")
    }

    @Test func `equivalent origin and canonical pad path preserve useful URL components`() throws {
        let data = Data(#"{"id":"P1","url":"https://app.coderpad.io:443/P1?view=code#main"}"#.utf8)
        let pad = try CoderPadClient.decoder.decode(Pad.self, from: data)
        let base = try #require(URL(string: "https://app.coderpad.io"))
        #expect(pad.webURL(fallbackBase: base) == pad.webURL)
    }

    @Test(arguments: [
        "https://other.coderpad.io/P1/playback", "https://app.coderpad.io/settings",
        "https://app.coderpad.io/P2/playback", "https://app.coderpad.io:444/P1/playback"
    ])
    func `playback rejects unrelated origins and routes`(_ raw: String) throws {
        let data = try JSONSerialization.data(withJSONObject: ["id": "P1", "playback": raw])
        let pad = try CoderPadClient.decoder.decode(Pad.self, from: data)
        let base = try #require(URL(string: "https://app.coderpad.io"))
        #expect(pad.playbackURL(fallbackBase: base) == nil)
    }

    @Test func `playback keeps owned deployment prefixes ports and query tokens`() throws {
        let raw = "https://self.coderpad.io:8443/team/P1/playback?token=abc#event"
        let data = try JSONSerialization.data(withJSONObject: ["id": "P1", "playback": raw])
        let pad = try CoderPadClient.decoder.decode(Pad.self, from: data)
        let base = try #require(URL(string: "https://self.coderpad.io:8443/team"))
        #expect(pad.playbackURL(fallbackBase: base)?.absoluteString == raw)
    }
}
