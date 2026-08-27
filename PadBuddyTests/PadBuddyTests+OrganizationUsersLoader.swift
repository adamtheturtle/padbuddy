//
//  PadBuddyTests+OrganizationUsersLoader.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Organization owner-picker loading")
@MainActor
struct OrganizationUsersLoaderTests {
    private struct LoadFailure: LocalizedError {
        var errorDescription: String? {
            "Directory unavailable"
        }
    }

    @Test func `a load failure becomes an actionable contextual outcome`() async throws {
        let outcome = try await OrganizationUsersLoader.load {
            throw LoadFailure()
        }

        guard case let .failed(message) = outcome else {
            Issue.record("Expected a visible failure outcome")
            return
        }

        #expect(message == "Could not load organization members — Directory unavailable")
    }

    @Test func `cancellation remains cancellation`() async {
        await #expect(throws: CancellationError.self) {
            try await OrganizationUsersLoader.load {
                throw CancellationError()
            }
        }
    }
}
