import Foundation
@testable import PadBuddy
import Testing

@Suite("Bounded pad title sort keys")
struct PadTitleSortBoundsTests {
    @Test func `oversized equal title prefixes use bounded stable identity ties`() throws {
        let prefix = String(repeating: "x", count: 500)
        let records = [["id": "first", "title": prefix + "z"], ["id": "second", "title": prefix + "a"]]
        let pads = try CoderPadClient.decoder.decode([Pad].self, from: JSONSerialization.data(withJSONObject: records))
        #expect(PadSort.titleAsc.sorted(pads).map(\.id) == ["first", "second"])
        #expect(PadSort.titleDesc.sorted(pads).map(\.id) == ["first", "second"])
    }
}
