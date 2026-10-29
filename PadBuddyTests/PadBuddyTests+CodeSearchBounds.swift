@testable import PadBuddy
import Testing

@Suite("Code search bounds")
struct CodeSearchBoundsTests {
    @Test func `ordinary matching preserves source indices and ignores case and accents`() {
        let source = "Café CAFE café"
        let matches = CodeSearch.highlights(of: "cafe", in: source)
        #expect(matches.ranges.map { String(source[$0]) } == ["Café", "CAFE", "café"])
        #expect(!matches.isLimited)
    }

    @Test func `repeated matches have bounded storage and report the limit`() {
        let source = String(repeating: "a", count: 10000)
        let matches = CodeSearch.highlights(of: "a", in: source)
        #expect(matches.ranges.count == CodeSearch.maximumMatches)
        #expect(matches.isLimited)
    }

    @Test func `oversized inputs skip synchronous highlighting without searching prefixes`() {
        let source = String(repeating: "a", count: CodeSearch.maximumSourceScalars + 1)
        let largeSource = CodeSearch.highlights(of: "a", in: source)
        #expect(largeSource.ranges.isEmpty)
        #expect(largeSource.isLimited)
        let largeQuery = CodeSearch.highlights(of: String(repeating: "a", count: 257), in: "a")
        #expect(largeQuery.ranges.isEmpty)
        #expect(largeQuery.isLimited)
        #expect(!CodeSearch.highlights(of: "", in: source).isLimited)
    }
}
