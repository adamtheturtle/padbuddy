//
//  coderpadTests+PadEvaluation.swift
//  coderpadTests
//
//  Unit coverage for the pure logic behind the per-pad evaluation layer (#591):
//  emptiness, the comma-separated tag parser, the Codable round-trip the local store
//  persists, and the iCloud last-writer-wins merge (#598). The store itself is a
//  UserDefaults/iCloud-backed singleton (UI glue), so these tests target the value
//  type's behaviour and the store's pure merge function rather than the store object.
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

@MainActor
@Suite("Pad evaluation iCloud merge")
struct PadEvaluationMergeTests {
    private let time0 = Date(timeIntervalSince1970: 1_000)
    private let time1 = Date(timeIntervalSince1970: 2_000)

    @Test("Cloud-only pads are added; neither device's pads are lost")
    func additiveUnion() {
        let local: [String: PadEvaluation] = ["mine": PadEvaluation(rating: 5)]
        let cloud: [String: PadEvaluation] = ["theirs": PadEvaluation(rating: 3)]
        let merged = PadEvaluationStore.merged(
            cloudEvaluations: cloud,
            cloudUpdatedAt: ["theirs": time0],
            localEvaluations: local,
            localUpdatedAt: ["mine": time0]
        )
        #expect(merged.evaluations == ["mine": PadEvaluation(rating: 5), "theirs": PadEvaluation(rating: 3)])
        #expect(merged.updatedAt == ["mine": time0, "theirs": time0])
    }

    @Test("A newer cloud edit wins for a pad present on both sides")
    func newerCloudWins() {
        let merged = PadEvaluationStore.merged(
            cloudEvaluations: ["p": PadEvaluation(rating: 4, notes: "cloud")],
            cloudUpdatedAt: ["p": time1],
            localEvaluations: ["p": PadEvaluation(rating: 2, notes: "local")],
            localUpdatedAt: ["p": time0]
        )
        #expect(merged.evaluations["p"] == PadEvaluation(rating: 4, notes: "cloud"))
        #expect(merged.updatedAt["p"] == time1)
    }

    @Test("An older or equal cloud edit does not overwrite the local one")
    func staleCloudIgnored() {
        let local: [String: PadEvaluation] = ["p": PadEvaluation(rating: 2, notes: "local")]
        let mergedOlder = PadEvaluationStore.merged(
            cloudEvaluations: ["p": PadEvaluation(rating: 4, notes: "cloud")],
            cloudUpdatedAt: ["p": time0],
            localEvaluations: local,
            localUpdatedAt: ["p": time1]
        )
        #expect(mergedOlder.evaluations["p"] == PadEvaluation(rating: 2, notes: "local"))
        #expect(mergedOlder.updatedAt["p"] == time1)

        // Equal timestamps are a tie the local side keeps (cloud must be strictly newer).
        let mergedEqual = PadEvaluationStore.merged(
            cloudEvaluations: ["p": PadEvaluation(rating: 4, notes: "cloud")],
            cloudUpdatedAt: ["p": time0],
            localEvaluations: local,
            localUpdatedAt: ["p": time0]
        )
        #expect(mergedEqual.evaluations["p"] == PadEvaluation(rating: 2, notes: "local"))
    }

    @Test("A missing timestamp is treated as the distant past")
    func missingTimestampLosesToTimestamped() {
        // Local has a real edit time; cloud lacks one, so local wins.
        let mergedLocalWins = PadEvaluationStore.merged(
            cloudEvaluations: ["p": PadEvaluation(rating: 4, notes: "cloud")],
            cloudUpdatedAt: [:],
            localEvaluations: ["p": PadEvaluation(rating: 2, notes: "local")],
            localUpdatedAt: ["p": time0]
        )
        #expect(mergedLocalWins.evaluations["p"] == PadEvaluation(rating: 2, notes: "local"))

        // Cloud has a real edit time; local lacks one, so cloud wins.
        let mergedCloudWins = PadEvaluationStore.merged(
            cloudEvaluations: ["p": PadEvaluation(rating: 4, notes: "cloud")],
            cloudUpdatedAt: ["p": time0],
            localEvaluations: ["p": PadEvaluation(rating: 2, notes: "local")],
            localUpdatedAt: [:]
        )
        #expect(mergedCloudWins.evaluations["p"] == PadEvaluation(rating: 4, notes: "cloud"))
    }
}
