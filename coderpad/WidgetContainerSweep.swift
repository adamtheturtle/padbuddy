//
//  WidgetContainerSweep.swift
//  coderpad
//
//  Retention for the widget's shared App Group container, split from
//  WidgetPadSnapshot.swift to keep both files under the file-length limit.
//

import Foundation
import OSLog

nonisolated extension WidgetSharedStore {
    /// Deletes shared-container debris the normal paths can't reach.
    ///
    /// Four kinds accumulate, all of them unbounded before this existed:
    ///
    /// - Pending handoff requests. Every New Pad / Open Pad tap writes one, and if
    ///   the app is never launched — or can't drain them — nothing removed them
    ///   (#2589). Old ones are dropped: replaying a tap from days ago would be
    ///   surprising anyway, and the newest is the one that matters.
    /// - `claimed-*.json`. A claim is deleted by the process that won it, so a
    ///   process that died between the rename and the cleanup left the file behind
    ///   forever, invisible to future drains (#2592).
    /// - `corrupt-*.json`, quarantined by a failed decode (#2593).
    /// - Per-account snapshots and favourites for accounts this install no longer
    ///   has: files left by a previous install, a migration, or a teardown that
    ///   didn't complete, still holding pad and question titles (#2603).
    ///
    /// `liveAccountIDs` is passed in rather than read from `AccountsStore.shared`,
    /// matching the rest of `WidgetSync`.
    static func sweepStaleFiles(liveAccountIDs: Set<String>) {
        guard let container = containerURL(purpose: "shared container sweep"),
              let urls = try? FileManager.default.contentsOfDirectory(
                  at: container, includingPropertiesForKeys: [.contentModificationDateKey]
              )
        else { return }

        let now = Date()
        var removed = 0
        for url in urls {
            let name = url.lastPathComponent
            let age = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
                .map { now.timeIntervalSince($0) } ?? 0
            guard shouldSweep(name: name, age: age, liveAccountIDs: liveAccountIDs) else { continue }

            do {
                try FileManager.default.removeItem(at: url)
                removed += 1
            } catch {
                logger.error("""
                Could not sweep widget file \(name, privacy: .private): \
                \(error.localizedDescription, privacy: .public)
                """)
            }
        }
        if removed > 0 {
            logger.info("Swept \(removed, privacy: .public) stale widget shared-container files")
        }
    }

    /// Whether the sweep should delete a file. Pure, so the policy is testable
    /// without touching the shared container.
    static func shouldSweep(name: String, age: TimeInterval, liveAccountIDs: Set<String>) -> Bool {
        // Typed claims preserve enough information for the next drain to recover
        // them after a crash, so never sweep them before that recovery runs (#1079).
        if claimedRequestOriginalName(name) != nil { return false }
        // Legacy opaque claims and quarantined corrupt payloads cannot be replayed.
        if name.hasPrefix(claimedRequestPrefix) || name.hasPrefix(corruptRequestPrefix) {
            return age > abandonedClaimLifetime
        }
        if name.hasPrefix(newPadRequestPrefix) || name.hasPrefix(openPadRequestPrefix) {
            return age > pendingRequestLifetime
        }
        // Per-account files name their account, so one whose account is gone is
        // orphaned. Only these two prefixes are account-keyed; the default snapshot
        // and the account index are not, and must survive.
        for prefix in [padsFilePrefix, favoritesFilePrefix] where name.hasPrefix(prefix) {
            let account = name.dropFirst(prefix.count).replacingOccurrences(of: ".json", with: "")
            return !liveAccountIDs.contains(String(account))
        }
        return false
    }

    /// How long an undrained handoff request is worth replaying.
    static let pendingRequestLifetime: TimeInterval = 24 * 60 * 60

    /// How long after a claim a file is assumed abandoned by the process that made it.
    static let abandonedClaimLifetime: TimeInterval = 10 * 60
}
