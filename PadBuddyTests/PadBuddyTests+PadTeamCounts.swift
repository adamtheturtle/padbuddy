import Foundation
@testable import PadBuddy
import Testing

@Suite("Cached pad team counts")
struct PadTeamCountsTests {
    @Test func `one pass preserves whitespace and Unicode case insensitive team matching`() throws {
        let names = ["Alpha", " ALPHA ", "Beta", "Σ", "ς", "Unrequested"]
        let records: [[String: Any]] = names.enumerated().map { index, name in
            ["id": "pad\(index)", "title": "Pad", "team": ["id": "team", "name": name]]
        }
        let pads = try CoderPadClient.decoder.decode([Pad].self, from: JSONSerialization.data(withJSONObject: records))
        let counts = PadTeamCounts.counts(in: pads, teams: ["Alpha", "Beta", "Σ"])
        #expect(counts.count == 3)
        #expect(PadTeamCounts.count(for: "Alpha", in: counts) == 2)
        #expect(PadTeamCounts.count(for: "Beta", in: counts) == 1)
        #expect(PadTeamCounts.count(for: "ς", in: counts) == 2)
        #expect(PadTeamCounts.count(for: "Unrequested", in: counts) == 0)
    }
}
