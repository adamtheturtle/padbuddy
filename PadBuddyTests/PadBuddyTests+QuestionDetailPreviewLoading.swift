//
//  PadBuddyTests+QuestionDetailPreviewLoading.swift
//  PadBuddyTests
//

import Foundation
import Testing
@testable import PadBuddy

#if DEBUG
    @Suite("Question detail preview loading")
    @MainActor
    struct QuestionDetailPreviewLoadingTests {
        private struct FixtureFailure: LocalizedError {
            var errorDescription: String? { "Fixture missing" }
        }

        @Test func `fixture failure becomes a visible contextual outcome`() async throws {
            let outcome = try await loadQuestionDetailPreview { throw FixtureFailure() }
            guard case let .failed(message) = outcome else {
                Issue.record("Expected preview failure state")
                return
            }
            #expect(message == "Could not load the question preview — Fixture missing")
        }

        @Test func `fixture cancellation remains cancellation`() async {
            await #expect(throws: CancellationError.self) {
                try await loadQuestionDetailPreview { throw CancellationError() }
            }
        }
    }
#endif
