//
//  PadBuddyTests+PreferenceCloudSync.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Preference cloud logical revisions")
@MainActor
struct PreferenceCloudLogicalRevisionTests {
    private struct DebounceFailure: Error {}

    @Test func `mirror debounce cancellation remains cancellation`() async {
        await #expect(throws: CancellationError.self) {
            try await PreferenceCloudSync.waitForMirrorDebounce { throw CancellationError() }
        }
    }

    @Test func `mirror debounce failure remains observable`() async {
        await #expect(throws: DebounceFailure.self) {
            try await PreferenceCloudSync.waitForMirrorDebounce { throw DebounceFailure() }
        }
    }

    @Test func `mirror retry cancellation remains cancellation`() async {
        await #expect(throws: CancellationError.self) {
            try await PreferenceCloudSync.waitForMirrorRetry { throw CancellationError() }
        }
    }

    @Test func `mirror readback requires both the value and revision`() {
        #expect(PreferenceCloudSync.mirrorReadbackMatches(
            local: "dark", revision: 7, cloud: "dark", cloudRevision: 7
        ))
        #expect(!PreferenceCloudSync.mirrorReadbackMatches(
            local: "dark", revision: 7, cloud: "light", cloudRevision: 7
        ))
        #expect(!PreferenceCloudSync.mirrorReadbackMatches(
            local: "dark", revision: 7, cloud: "dark", cloudRevision: 6
        ))
    }

    @Test func `only the failed value is treated as a mirror retry`() {
        #expect(PreferenceCloudSync.mirrorRetryMatches(
            pendingValue: "dark", localValue: "dark"
        ))
        #expect(!PreferenceCloudSync.mirrorRetryMatches(
            pendingValue: "dark", localValue: "light"
        ))
        #expect(PreferenceCloudSync.mirrorRetryMatches(
            pendingValue: nil, localValue: nil
        ))
    }

    @Test func `mirror retries yield to winning concurrent cloud writes`() {
        #expect(PreferenceCloudSync.retryShouldYieldToCloud(
            local: "dark", cloud: "light", previousCloud: "dark",
            localRevision: 7, cloudRevision: 7
        ))
        #expect(!PreferenceCloudSync.retryShouldYieldToCloud(
            local: "light", cloud: "dark", previousCloud: "light",
            localRevision: 7, cloudRevision: 7
        ))
        #expect(PreferenceCloudSync.retryShouldYieldToCloud(
            local: "dark", cloud: nil, previousCloud: "light",
            localRevision: 7, cloudRevision: 7
        ))
        #expect(!PreferenceCloudSync.retryShouldYieldToCloud(
            local: "dark", cloud: "light", previousCloud: "dark",
            localRevision: 8, cloudRevision: 7
        ))
        #expect(!PreferenceCloudSync.retryShouldYieldToCloud(
            local: "dark", cloud: "light", previousCloud: "light",
            localRevision: 7, cloudRevision: 7
        ))
    }

    @Test func `mirror retries compare complete revision stamps`() {
        let maximum = PreferenceCloudSync.maximumRevision
        let older = PreferenceRevisionStamp(era: 1, revision: maximum)
        let newer = PreferenceRevisionStamp(era: 2, revision: maximum)

        #expect(PreferenceCloudSync.retryShouldYieldToCloud(
            local: "dark", cloud: "light", previousCloud: "dark",
            revisions: (local: older, cloud: newer)
        ))
        #expect(!PreferenceCloudSync.retryShouldYieldToCloud(
            local: "dark", cloud: "light", previousCloud: "dark",
            revisions: (local: newer, cloud: older)
        ))
    }

    @Test func `mirror readback requires the revision era`() {
        let maximum = PreferenceCloudSync.maximumRevision
        let expected = PreferenceRevisionStamp(era: 2, revision: maximum)

        #expect(PreferenceCloudSync.mirrorReadbackMatches(
            local: "dark", revision: expected, cloud: "dark",
            cloudRevision: maximum, cloudEra: 2
        ))
        #expect(!PreferenceCloudSync.mirrorReadbackMatches(
            local: "dark", revision: expected, cloud: "dark",
            cloudRevision: maximum, cloudEra: 1
        ))
    }

    @Test
    func `local edits advance beyond skewed and legacy stamps`() {
        #expect(PreferenceCloudSync.nextRevision(local: 12, cloud: 1_900_000_000) == 1_900_000_001)
        #expect(PreferenceCloudSync.nextRevision(local: 1_900_000_001, cloud: 4) == 1_900_000_002)
    }

    @Test
    func `local edits cannot emit nonfinite or overflowing revisions`() {
        let maximum = PreferenceCloudSync.maximumRevision
        #expect(PreferenceCloudSync.nextRevision(local: .nan, cloud: 4) == 5)
        #expect(PreferenceCloudSync.nextRevision(local: .infinity, cloud: 4) == 5)
        #expect(PreferenceCloudSync.nextRevision(local: -.infinity, cloud: 4) == 5)
        #expect(PreferenceCloudSync.nextRevision(local: .greatestFiniteMagnitude, cloud: maximum) == maximum)
    }

    @Test
    func `local edits advance into a new era after revision saturation`() {
        let saturated = PreferenceRevisionStamp(
            era: 0,
            revision: PreferenceCloudSync.maximumRevision
        )
        let first = PreferenceCloudSync.nextRevisionStamp(local: saturated, cloud: saturated)
        let second = PreferenceCloudSync.nextRevisionStamp(local: first, cloud: saturated)

        #expect(first == PreferenceRevisionStamp(
            era: 1,
            revision: PreferenceCloudSync.maximumRevision
        ))
        #expect(second == PreferenceRevisionStamp(
            era: 2,
            revision: PreferenceCloudSync.maximumRevision
        ))
        #expect(second > first)
    }

    @Test
    func `an era is ignored until its saturated revision is delivered`() {
        #expect(PreferenceCloudSync.revisionStamp(revision: nil, era: 2)
            == PreferenceRevisionStamp(era: 0, revision: 0))
        #expect(PreferenceCloudSync.revisionStamp(revision: 7, era: 2)
            == PreferenceRevisionStamp(era: 0, revision: 7))
        #expect(PreferenceCloudSync.revisionStamp(
            revision: PreferenceCloudSync.maximumRevision,
            era: 2
        ) == PreferenceRevisionStamp(
            era: 2,
            revision: PreferenceCloudSync.maximumRevision
        ))
    }

    @Test
    func `a newer revision era outranks value ordering`() {
        let maximum = PreferenceCloudSync.maximumRevision
        #expect(PreferenceCloudSync.shouldAdoptCloudValue(
            "dark", forKey: "general.appearance", local: "light",
            cloudRevision: PreferenceRevisionStamp(era: 2, revision: maximum),
            localRevision: PreferenceRevisionStamp(era: 1, revision: maximum)
        ))
    }

    @Test
    func `revision notifications route back to their preference`() {
        let key = "general.appearance"
        #expect(PreferenceCloudSync.preferenceKey(forCloudChangeKey: key) == key)
        #expect(PreferenceCloudSync.preferenceKey(forCloudChangeKey: "revision.\(key)") == key)
        #expect(PreferenceCloudSync.preferenceKey(forCloudChangeKey: "revisionEra.\(key)") == key)
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
    private struct DecodeFailure: LocalizedError {
        let errorDescription: String?
    }

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

    @Test
    func `filter snapshot failures retain both schema contexts`() {
        let outcome = PreferenceCloudSync.decodeFilterSnapshot(
            Data(),
            snapshot: { _ in throw DecodeFailure(errorDescription: "Bad envelope") },
            legacy: { _ in throw DecodeFailure(errorDescription: "Bad legacy search") }
        )

        guard case let .invalid(detail) = outcome else {
            Issue.record("Expected invalid filter snapshot")
            return
        }

        #expect(detail == "Filter snapshot decode failed: Bad envelope; legacy decode failed: Bad legacy search")
    }

    @Test
    func `invalid inbound values cannot win or mask a corrected value`() {
        let invalid: Any = "unknown"
        let corrected: Any = "dark"
        #expect(PreferenceCloudSync.preferenceValueDisposition(invalid,
                                                               forKey: "general.appearance") == .invalid)
        #expect(PreferenceCloudSync.preferenceValueDisposition(corrected,
                                                               forKey: "general.appearance") == .value)
        #expect(!PreferenceCloudSync.shouldAdoptCloudValue(
            invalid, forKey: "general.appearance", local: "light", cloudRevision: 8, localRevision: 7
        ))
        #expect(PreferenceCloudSync.shouldAdoptCloudValue(
            corrected, forKey: "general.appearance", local: "light", cloudRevision: 8, localRevision: 7
        ))
        #expect(!PreferenceCloudSync.shouldAdoptCloudValue(
            corrected, forKey: "general.appearance", local: "light", cloudRevision: 6, localRevision: 7
        ))
    }
}
