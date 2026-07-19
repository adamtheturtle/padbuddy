//
//  coderpadTests+PreferenceCloudSync.swift
//  coderpadTests
//

@testable import CoderPad
import Testing

@Suite("Preference cloud logical revisions")
@MainActor
struct PreferenceCloudLogicalRevisionTests {
    @Test
    func `local edits advance beyond skewed and legacy stamps`() {
        #expect(PreferenceCloudSync.nextRevision(local: 12, cloud: 1_900_000_000) == 1_900_000_001)
        #expect(PreferenceCloudSync.nextRevision(local: 1_900_000_001, cloud: 4) == 1_900_000_002)
    }

    @Test
    func `revision notifications route back to their preference`() {
        let key = "general.appearance"
        #expect(PreferenceCloudSync.preferenceKey(forCloudChangeKey: key) == key)
        #expect(PreferenceCloudSync.preferenceKey(forCloudChangeKey: "revision.\(key)") == key)
        #expect(PreferenceCloudSync.preferenceKey(forCloudChangeKey: "revision.unknown") == nil)
        #expect(PreferenceCloudSync.preferenceKey(forCloudChangeKey: "unknown") == nil)
    }

    @Test
    func `only a current deletion tombstone removes local state`() {
        #expect(PreferenceCloudSync.deletionWins(cloudRevision: 11, localRevision: 10, localExists: true))
        #expect(PreferenceCloudSync.deletionWins(cloudRevision: 10, localRevision: 10, localExists: true))
        #expect(!PreferenceCloudSync.deletionWins(cloudRevision: 9, localRevision: 10, localExists: true))
        #expect(!PreferenceCloudSync.deletionWins(cloudRevision: 0, localRevision: 0, localExists: true))
        #expect(!PreferenceCloudSync.deletionWins(cloudRevision: 10, localRevision: 10, localExists: false))
    }
}

@Suite("Preference cloud outbound validation")
@MainActor
struct PreferenceCloudOutboundValidationTests {
    @Test
    func `enum and boolean preferences require their exact schema`() {
        #expect(PreferenceCloudSync.preferenceValueDisposition("updatedDesc", forKey: "pads.sort") == .value)
        #expect(PreferenceCloudSync.preferenceValueDisposition("unknown", forKey: "pads.sort") == .invalid)
        #expect(PreferenceCloudSync.preferenceValueDisposition(true,
                                                               forKey: "general.spotlightIndexing") == .value)
        #expect(PreferenceCloudSync.preferenceValueDisposition(1,
                                                               forKey: "general.spotlightIndexing") == .invalid)
        #expect(PreferenceCloudSync.preferenceValueDisposition("true",
                                                               forKey: "general.spotlightIndexing") == .invalid)
    }

    @Test
    func `deletion is distinct from invalid data`() {
        #expect(PreferenceCloudSync.preferenceValueDisposition(nil, forKey: "general.appearance") == .deletion)
        #expect(PreferenceCloudSync.preferenceValueDisposition(Data("bad".utf8),
                                                               forKey: "general.appearance") == .invalid)
    }

    @Test
    func `filter snapshots must decode and contain valid enum-like filters`() throws {
        let valid = NamedSearch(name: "", typeFilter: "live", draftFilter: "draft")
        let invalid = NamedSearch(name: "", typeFilter: "not-a-type")
        let current = MergedFilterSnapshot(search: valid, mineOnly: true)
        #expect(try PreferenceCloudSync.preferenceValueDisposition(
            SharedCoders.encoder.encode(valid), forKey: "pads.merged.liveFilter"
        ) == .value)
        #expect(try PreferenceCloudSync.preferenceValueDisposition(
            SharedCoders.encoder.encode(invalid), forKey: "pads.merged.liveFilter"
        ) == .invalid)
        #expect(try PreferenceCloudSync.preferenceValueDisposition(
            SharedCoders.encoder.encode(current), forKey: "questions.merged.liveFilter"
        ) == .value)
        #expect(PreferenceCloudSync.preferenceValueDisposition(
            Data("not json".utf8), forKey: "pads.merged.liveFilter"
        ) == .invalid)
    }
}
