//
//  PreferenceCloudSync+Revision.swift
//  coderpad
//

import Foundation

struct PendingMirrorRetry {
    let value: Any?
    let previousCloudValue: Any?
}

struct PreferenceRevisionStamp: Comparable, Equatable {
    let era: Double
    let revision: Double

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.era != rhs.era ? lhs.era < rhs.era : lhs.revision < rhs.revision
    }
}

extension PreferenceCloudSync {
    /// Revisions remain exact integers below this ceiling when stored as doubles.
    /// Saturating corrupt or exhausted counters keeps comparisons deterministic and
    /// prevents a non-finite value from poisoning every later edit.
    static let maximumRevision = 9_000_000_000_000_000.0

    static func normalizedRevision(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return 0 }

        return min(value, maximumRevision)
    }

    /// The KVS key carrying `key`'s revision stamp. Internal for tests.
    static func cloudRevisionKey(_ key: String) -> String {
        "revision.\(key)"
    }

    /// The device-local UserDefaults key remembering the revision of the last write.
    static func localRevisionKey(_ key: String) -> String {
        "cloud.revision.\(key)"
    }

    static func cloudRevisionEraKey(_ key: String) -> String {
        "revisionEra.\(key)"
    }

    static func localRevisionEraKey(_ key: String) -> String {
        "cloud.revisionEra.\(key)"
    }

    static func preferenceKey(forCloudChangeKey changedKey: String) -> String? {
        if syncedKeys.contains(changedKey) {
            return changedKey
        }
        for prefix in ["revision.", "revisionEra."] where changedKey.hasPrefix(prefix) {
            let key = String(changedKey.dropFirst(prefix.count))
            return syncedKeys.contains(key) ? key : nil
        }
        return nil
    }

    static func deletionWins(cloudRevision: Double, localRevision: Double, localExists: Bool) -> Bool {
        guard cloudRevision > 0 else { return false }

        if cloudRevision != localRevision {
            return cloudRevision > localRevision
        }
        return localExists
    }

    static func deletionWins(
        cloudRevision: PreferenceRevisionStamp,
        localRevision: PreferenceRevisionStamp,
        localExists: Bool
    ) -> Bool {
        guard cloudRevision > PreferenceRevisionStamp(era: 0, revision: 0) else { return false }

        return cloudRevision != localRevision ? cloudRevision > localRevision : localExists
    }

    /// A Lamport-style revision beyond every replica observed for a local edit.
    /// Shipped wall-clock revisions remain numeric baselines for a safe upgrade.
    static func nextRevision(local: Double, cloud: Double) -> Double {
        let baseline = max(normalizedRevision(local), normalizedRevision(cloud))
        return min(baseline + 1, maximumRevision)
    }

    static func mirrorReadbackMatches(
        local: Any?, revision: Double, cloud: Any?, cloudRevision: Any?
    ) -> Bool {
        plistValuesEqual(local, cloud)
            && Self.revision(cloudRevision) == normalizedRevision(revision)
    }

    static func mirrorReadbackMatches(
        local: Any?, revision: PreferenceRevisionStamp,
        cloud: Any?, cloudRevision: Any?, cloudEra: Any?
    ) -> Bool {
        plistValuesEqual(local, cloud)
            && revisionStamp(revision: cloudRevision, era: cloudEra) == revision
    }

    static func mirrorRetryMatches(pendingValue: Any?, localValue: Any?) -> Bool {
        plistValuesEqual(pendingValue, localValue)
    }

    static func mirrorRetryMatches(_ retry: PendingMirrorRetry?, localValue: Any?) -> Bool {
        retry.map { mirrorRetryMatches(pendingValue: $0.value, localValue: localValue) } ?? false
    }

    static func retryShouldYieldToCloud(
        local: Any?, cloud: Any?, previousCloud: Any?,
        localRevision: Double, cloudRevision: Double
    ) -> Bool {
        if cloudRevision != localRevision {
            return cloudRevision > localRevision
        }
        guard cloudRevision > 0 else { return false }
        guard !plistValuesEqual(cloud, previousCloud) else { return false }
        guard let cloud else { return local != nil }

        return tieBreakFavorsCloud(local: local, cloud: cloud)
    }

    static func retryShouldYieldToCloud(
        local: Any?, cloud: Any?, previousCloud: Any?,
        revisions: (local: Double, cloud: Double)
    ) -> Bool {
        retryShouldYieldToCloud(
            local: local, cloud: cloud, previousCloud: previousCloud,
            localRevision: revisions.local, cloudRevision: revisions.cloud
        )
    }

    static func retryShouldYieldToCloud(
        local: Any?, cloud: Any?, previousCloud: Any?,
        revisions: (local: PreferenceRevisionStamp, cloud: PreferenceRevisionStamp)
    ) -> Bool {
        if revisions.cloud != revisions.local {
            return revisions.cloud > revisions.local
        }
        guard revisions.cloud > PreferenceRevisionStamp(era: 0, revision: 0) else { return false }
        guard !plistValuesEqual(cloud, previousCloud) else { return false }
        guard let cloud else { return local != nil }

        return tieBreakFavorsCloud(local: local, cloud: cloud)
    }

    static func mirrorRevisions(
        forKey key: String
    ) -> (cloud: PreferenceRevisionStamp, local: PreferenceRevisionStamp) {
        let cloud = revisionStamp(
            revision: CloudSyncStore.shared.object(forKey: cloudRevisionKey(key)),
            era: CloudSyncStore.shared.object(forKey: cloudRevisionEraKey(key))
        )
        let local = revisionStamp(
            revision: UserDefaults.standard.object(forKey: localRevisionKey(key)),
            era: UserDefaults.standard.object(forKey: localRevisionEraKey(key))
        )
        return (cloud, local)
    }

    /// Whether this key's local value was stamped as newer than the cloud copy but never
    /// uploaded — the state an interrupted mirror leaves behind (#4644).
    static func hasUnmirroredLocalEdit(key: String) -> Bool {
        let revisions = mirrorRevisions(forKey: key)
        return revisions.local > revisions.cloud
    }

    static func waitForMirrorRetry(using sleep: (() async throws -> Void)? = nil) async throws {
        if let sleep {
            try await sleep()
        } else {
            try await Task.sleep(for: .seconds(2))
        }
    }

    static func waitForMirrorDebounce(using sleep: (() async throws -> Void)? = nil) async throws {
        if let sleep {
            try await sleep()
        } else {
            try await Task.sleep(for: .milliseconds(500))
        }
    }

    static func revisionStamp(revision: Any?, era: Any?) -> PreferenceRevisionStamp {
        let revision = Self.revision(revision)
        return PreferenceRevisionStamp(
            era: revision == maximumRevision ? Self.revision(era) : 0,
            revision: revision
        )
    }

    static func nextRevisionStamp(
        local: PreferenceRevisionStamp,
        cloud: PreferenceRevisionStamp
    ) -> PreferenceRevisionStamp {
        let baseline = max(local, cloud)
        if baseline.era > 0 || baseline.revision == maximumRevision {
            return PreferenceRevisionStamp(
                era: nextRevision(local: local.era, cloud: cloud.era),
                revision: maximumRevision
            )
        }
        return PreferenceRevisionStamp(
            era: 0,
            revision: nextRevision(local: local.revision, cloud: cloud.revision)
        )
    }
}
