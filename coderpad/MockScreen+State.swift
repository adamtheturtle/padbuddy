//
//  MockScreen+State.swift
//  coderpad
//
//  Per-client mutable state for the fake Screen API. Invitations sent, sessions
//  cancelled or deleted, and the webhook URL are layered over the immutable seed data
//  in `MockScreenFixtures`. Each `API-Key` gets its own `MockScreenState` (see
//  `MockScreenStateRegistry`) so the demo account and every test have an isolated store.
//

import Foundation
import Synchronization

final nonisolated class MockScreenState: @unchecked Sendable {
    /// Serializes access to the mutable state below. Per-state rather than global, so
    /// requests to different keys never contend while concurrent requests to the same
    /// state stay serialized. The `@unchecked Sendable` vouches that every access to the
    /// stored properties happens under this lock.
    let lock = Mutex(())

    /// The configured webhook callback URL, or `nil` when none is set.
    var webhookURL: String?
    /// Sessions created during the session via `POST /campaigns/:id/actions/send`.
    var createdTests: [[String: Any]] = []
    /// Sessions whose status has been overridden to "cancelled".
    var cancelledTestIDs: Set<Int> = []
    /// Sessions removed via `DELETE /tests/:id`.
    var deletedTestIDs: Set<Int> = []
    /// The next id handed to an invitation-created session, above the seed id range.
    var nextTestID = 9000

    /// Seed and invitation-created sessions, with cancellations applied and deletions
    /// removed — the single source the test routes read.
    func allTests() -> [[String: Any]] {
        (MockScreenFixtures.tests() + createdTests).compactMap { test in
            guard let id = test["id"] as? Int else { return test }

            if deletedTestIDs.contains(id) { return nil }

            var session = test
            if cancelledTestIDs.contains(id) { session["status"] = "cancelled" }
            return session
        }
    }
}

/// Maps an `API-Key` to its `MockScreenState`, creating one on first use. The app's demo
/// account uses the stable key "demo" (one shared store for the session); tests can pass
/// a unique key each so their mutations never collide.
nonisolated enum MockScreenStateRegistry {
    private static let lock = Mutex([String: MockScreenState]())

    static func state(forKey key: String) -> MockScreenState {
        lock.withLock { registry in
            if let existing = registry[key] { return existing }

            let created = MockScreenState()
            registry[key] = created
            return created
        }
    }
}
