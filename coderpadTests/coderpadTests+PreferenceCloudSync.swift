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
