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
    static let legacyCorruptRequestPrefix = "corrupt-"

    /// Deletes shared-container debris the normal paths can't reach.
    ///
    /// Per-account snapshots and favourites for accounts this install no longer
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
            let age: TimeInterval
            do {
                let modified = try url.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate
                age = modified.map { now.timeIntervalSince($0) } ?? 0
            } catch {
                logger.error("Could not inspect widget file age for \(name, privacy: .private)")
                age = 0
            }
            guard shouldSweep(name: name, liveAccountIDs: liveAccountIDs, age: age) else { continue }

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
    static func shouldSweep(
        name: String,
        liveAccountIDs: Set<String>,
        age: TimeInterval = 0
    ) -> Bool {
        // Pre-mailbox malformed payloads were quarantined at the container root.
        // Only the two exact legacy UUID shapes are ours; a different shared file
        // that happens to begin with "corrupt-" must survive (#4173).
        if isLegacyCorruptHandoffFile(name) {
            return age > abandonedClaimLifetime || age < -futureModificationTolerance
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

    static func isLegacyCorruptHandoffFile(_ name: String) -> Bool {
        guard name.hasPrefix(legacyCorruptRequestPrefix), name.hasSuffix(".json") else { return false }

        var identity = String(name.dropFirst(legacyCorruptRequestPrefix.count).dropLast(5))
        if identity.hasPrefix("overflow-") {
            identity.removeFirst("overflow-".count)
        }
        return UUID(uuidString: identity) != nil
    }
}
