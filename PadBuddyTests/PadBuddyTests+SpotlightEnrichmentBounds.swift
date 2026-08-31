@testable import PadBuddy
import Testing

@Suite("Spotlight enrichment bounds")
struct SpotlightEnrichmentBoundsTests {
    @Test func `candidate fields are bounded before enrichment work`() throws {
        let content = try #require(SpotlightIndexer.boundedQuestionEnrichmentContent(
            title: String(repeating: "t", count: 1000),
            language: String(repeating: "l", count: 1000),
            description: String(repeating: "d", count: 20000)
        ))

        #expect(content.title.count == SpotlightIndexer.maxEnrichmentTitleCharacters)
        #expect(content.language?.count == SpotlightIndexer.maxEnrichmentLanguageCharacters)
        #expect(content.description.count == SpotlightIndexer.maxEnrichmentDescriptionCharacters)
    }

    @Test func `bounded whitespace-only descriptions are not enrichable`() {
        #expect(SpotlightIndexer.boundedQuestionEnrichmentContent(
            title: "Question", language: nil,
            description: String(repeating: " ", count: 20000) + "hidden tail"
        ) == nil)
    }
}
