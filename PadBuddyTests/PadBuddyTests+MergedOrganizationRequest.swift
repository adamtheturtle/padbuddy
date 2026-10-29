//
//  PadBuddyTests+MergedOrganizationRequest.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Merged organization secondary requests")
struct MergedOrganizationRequestTests {
    private struct RequestFailure: LocalizedError {
        var message = "Server unavailable"
        var errorDescription: String? {
            message
        }
    }

    @Test func `remote failure messages have separate display and diagnostic budgets`() {
        let failure = RequestFailure(message: "server\n\u{202E}" + String(repeating: "x", count: 10000))
        let display = MergedOrganizationRequest.displayMessage(failure)
        let diagnostic = MergedOrganizationRequest.diagnostic(failure)
        #expect(display.unicodeScalars.count <= 512)
        #expect(diagnostic.unicodeScalars.count <= 2048)
        #expect(diagnostic.count > display.count)
        #expect(!display.contains("\n"))
        #expect(!diagnostic.contains("\u{202E}"))
    }

    @Test func `stats failure retains request context`() async throws {
        let outcome: MergedOrganizationRequestOutcome<String> = try await MergedOrganizationRequest.evaluate(
            context: "Could not refresh pad stats",
            load: { throw RequestFailure() }
        )

        guard case let .failed(message) = outcome else {
            Issue.record("Expected a failed stats request")
            return
        }

        #expect(message == "Could not refresh pad stats: Server unavailable")
    }

    @Test func `cancelled stats request remains cancellation`() async {
        do {
            let _: MergedOrganizationRequestOutcome<String> = try await MergedOrganizationRequest.evaluate(
                context: "Could not refresh pad stats",
                load: { throw CancellationError() }
            )
            Issue.record("Expected cancellation")
        } catch is CancellationError {
            // Expected: a cancelled reload does not continue into quota work.
        } catch {
            Issue.record("Expected CancellationError, got \(error)")
        }
    }
}
