//
//  PreferenceCloudSync+Revision.swift
//  coderpad
//

import Foundation

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

    static func preferenceKey(forCloudChangeKey changedKey: String) -> String? {
        if syncedKeys.contains(changedKey) {
            return changedKey
        }
        let prefix = "revision."
        guard changedKey.hasPrefix(prefix) else { return nil }

        let key = String(changedKey.dropFirst(prefix.count))
        return syncedKeys.contains(key) ? key : nil
    }

    static func deletionWins(cloudRevision: Double, localRevision: Double, localExists: Bool) -> Bool {
        guard cloudRevision > 0 else { return false }

        if cloudRevision != localRevision {
            return cloudRevision > localRevision
        }
        return localExists
    }

    /// A Lamport-style revision beyond every replica observed for a local edit.
    /// Shipped wall-clock revisions remain numeric baselines for a safe upgrade.
    static func nextRevision(local: Double, cloud: Double) -> Double {
        let baseline = max(normalizedRevision(local), normalizedRevision(cloud))
        return min(baseline + 1, maximumRevision)
    }
}
