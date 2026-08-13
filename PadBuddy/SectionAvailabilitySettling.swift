//
//  SectionAvailabilitySettling.swift
//  coderpad
//
//  How long a section must stay unavailable before the app navigates away from it.
//

import Foundation

enum SectionAvailabilitySettling {
    /// A section that has just become unavailable is left alone for this long before
    /// the user is moved off it.
    ///
    /// Availability is derived from live state that can dip transiently: `Screen`
    /// depends on a keychain read that can momentarily fail during an account refresh,
    /// and `Quota`'s unlimited flag comes from a cache that a stale or in-flight
    /// response can briefly answer wrongly. Reacting to the first false reading threw
    /// away the user's Screen drill-down or quota page — and their scroll position and
    /// selection with it — for a condition that resolved a moment later (#2247, #2252).
    ///
    /// A genuine change (a key removed, a switch to the combined view) still moves them
    /// off, just after this settles rather than instantly.
    static let grace: Duration = .milliseconds(1200)

    static func wait(using sleep: (() async throws -> Void)? = nil) async throws {
        if let sleep {
            try await sleep()
        } else {
            try await Task.sleep(for: grace)
        }
    }

    static func shouldContinue(context: String) async -> Bool {
        do {
            try await wait()
            return true
        } catch is CancellationError {
            return false
        } catch {
            assertionFailure("\(context) availability settling failed: \(error)")
            return false
        }
    }
}
