import Foundation
@testable import PadBuddy
import Testing

@Suite("Favorite entity input bounds")
struct FavoriteEntityInputBoundsTests {
    @Test func `oversized and malformed requested identifiers have no aliases`() {
        let oversized = String(repeating: "x", count: 1_000_000)
        #expect(FavoriteQuestionQuery.wantedIdentifiers(for: [oversized, "sync|bad", "invalid:42"]).isEmpty)
        #expect(FavoriteQuestionQuery.keyIndependentID(oversized).isEmpty)
        let ids = (1 ... FavoriteQuestionQuery.maximumIdentifiers + 10).map { "\(UUID()):\($0)" }
        #expect(FavoriteQuestionQuery.boundedIdentifiers(ids).count == FavoriteQuestionQuery.maximumIdentifiers)
        #expect(!FavoriteQuestionQuery.wantedIdentifiers(for: ids).contains(ids.last ?? ""))
    }
}
