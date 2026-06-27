//
//  coderpadTests+PadEvaluation.swift
//  coderpadTests
//
//  Unit coverage for the pure logic behind the per-pad evaluation layer (#591):
//  emptiness, the comma-separated tag parser, and the Codable round-trip the local
//  store persists. The store itself is a UserDefaults-backed singleton (UI glue), so
//  these tests target the value type's behaviour rather than the store.
//

@testable import CoderPad
import Foundation
import Testing

@Suite("Pad evaluation")
struct PadEvaluationTests {
    @Test("A fresh evaluation is empty; any field makes it non-empty")
    func emptiness() {
        #expect(PadEvaluation().isEmpty)
        #expect(!PadEvaluation(rating: 3).isEmpty)
        #expect(!PadEvaluation(notes: "hi").isEmpty)
        #expect(!PadEvaluation(tags: ["x"]).isEmpty)
    }

    @Test("Tag parsing trims, drops empties, and de-duplicates case-insensitively in order")
    func tagParsing() {
        #expect(PadEvaluation.parseTags(from: "  strong ,  follow-up ") == ["strong", "follow-up"])
        // Empties between/around commas are dropped.
        #expect(PadEvaluation.parseTags(from: ",a,,b,") == ["a", "b"])
        // Case-insensitive dedup keeps the first spelling and the typed order.
        #expect(PadEvaluation.parseTags(from: "Swift, swift, SWIFT, iOS") == ["Swift", "iOS"])
        // Nothing meaningful yields no tags.
        #expect(PadEvaluation.parseTags(from: "   ,  , ").isEmpty)
        #expect(PadEvaluation.parseTags(from: "").isEmpty)
    }

    @Test("An evaluation round-trips through JSON unchanged")
    func codableRoundTrip() throws {
        let original = PadEvaluation(rating: 4, notes: "Solid on recursion", tags: ["hire", "backend"])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PadEvaluation.self, from: data)
        #expect(decoded == original)
    }

    @Test("A keyed map of evaluations round-trips, matching how the store persists")
    func mapRoundTrip() throws {
        let map: [String: PadEvaluation] = [
            "abc123": PadEvaluation(rating: 5, notes: "", tags: ["strong"]),
            "def456": PadEvaluation(rating: 0, notes: "follow up", tags: [])
        ]
        let data = try JSONEncoder().encode(map)
        let decoded = try JSONDecoder().decode([String: PadEvaluation].self, from: data)
        #expect(decoded == map)
    }
}
