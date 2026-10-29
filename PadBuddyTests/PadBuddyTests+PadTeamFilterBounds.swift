@testable import PadBuddy
import Testing

@Suite("Pad team filter identity bounds")
struct PadTeamFilterBoundsTests {
    @Test func `team options reject oversized or multiline text and retain bounded labels`() {
        let invalid = [String(repeating: "x", count: 1_000_000), "bad\u{202e}name", "bad\u{2028}name", "\n"]
        #expect(FilterOptionValues.boundedTeams(invalid.map(Optional.some)).isEmpty)
        #expect(FilterOptionValues.boundedTeams([" Team  A ", "Team  A"]) == ["Team  A"])
        let names = (0 ..< 1000).map { Optional("Team \($0)") }
        #expect(FilterOptionValues.boundedTeams(names).count == FilterOptionValues.maximumOptions)
    }
}
