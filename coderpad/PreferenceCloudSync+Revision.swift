//
//  PreferenceCloudSync+Revision.swift
//  coderpad
//

import Foundation

extension PreferenceCloudSync {
    /// A Lamport-style revision beyond every replica observed for a local edit.
    /// Shipped wall-clock revisions remain numeric baselines for a safe upgrade.
    static func nextRevision(local: Double, cloud: Double) -> Double {
        max(local, cloud) + 1
    }
}
