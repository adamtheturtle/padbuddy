import Foundation
@testable import PadBuddy
import Testing

@Suite("Bounded merged pad routing")
@MainActor
struct MergedPadRouteIndexTests {
    @Test func `later collisions remain ambiguous after the route budget is full`() throws {
        let ids = ["first", "second", "omitted", String(repeating: "x", count: 1_000_000)]
        let records = ids.map { ["id": $0, "title": "Pad"] }
        let pads = try CoderPadClient.decoder.decode([Pad].self, from: JSONSerialization.data(withJSONObject: records))
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let routes = MergedPadRouteIndex.build([
            (first, pads), (second, [pads[0]]), (third, [pads[0]])
        ], maximum: 2)
        #expect(routes.count == 2)
        #expect(routes["first"]?.count == 2)
        #expect(routes["second"] == [first])
        #expect(routes["omitted"] == nil)
        let router = MergedRouting()
        router.setPadRoutes(routes)
        #expect(router.uniqueAccountID(forPadID: "first") == nil)
        #expect(router.uniqueAccountID(forPadID: "second") == first)
    }
}
