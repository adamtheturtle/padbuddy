//
//  PadBuddyTests+ScreenActionFailures.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Screen action failure context")
struct ScreenActionFailureTests {
    @Test
    func `failure identifies operation candidate session and account`() {
        let failure = ScreenActionFailure(
            operation: "Cancel invitation",
            testID: 42,
            candidate: "Ada Lovelace",
            accountName: "Acme EU",
            reason: "The request timed out."
        )

        #expect(failure.detail.contains("Cancel invitation"))
        #expect(failure.detail.contains("Ada Lovelace"))
        #expect(failure.detail.contains("#42"))
        #expect(failure.detail.contains("Acme EU"))
        #expect(failure.detail.contains("The request timed out."))
    }
}

@Suite("Screen cancel reconciliation")
struct ScreenCancelReconciliationTests {
    @Test func `failed refetch retains the row as cancelled`() throws {
        let current = try ScreenTestSession(id: 42, status: "waiting", candidateName: "Ada")
        let reconciled = ScreenCancelReconciliation.session(current: current, fresh: nil)
        #expect(reconciled.id == current.id)
        #expect(reconciled.candidateName == current.candidateName)
        #expect(reconciled.status == "cancelled")
    }

    @Test func `successful refetch replaces the local row`() throws {
        let current = try ScreenTestSession(id: 42, status: "waiting")
        let fresh = try ScreenTestSession(id: 42, status: "aborted", candidateName: "Fresh")
        #expect(ScreenCancelReconciliation.session(current: current, fresh: fresh) == fresh)
    }
}

@Suite("Screen campaign diagnostics")
struct ScreenCampaignDiagnosticTests {
    @Test func `tolerant campaign list counts discarded records`() async throws {
        let result = try await screenClient().listCampaignsResult()

        #expect(result.campaigns.map(\.id) == [42, 43])
        #expect(result.discardedCount == 4)
        #expect(result.diagnostic != nil)
    }
}

@Suite("Screen session diagnostics")
struct ScreenSessionDiagnosticTests {
    @Test func `page counts discarded candidate sessions`() throws {
        let data = Data(
            #"{"tests":[{"id":1,"status":"waiting"},{"status":"waiting"},{"id":0},{"id":-1}],"pagination":null}"#.utf8
        )
        let page = try JSONDecoder().decode(ScreenTestsPage.self, from: data)
        #expect(page.tests.map(\.id) == [1])
        #expect(page.discardedTestCount == 3)
        #expect(page.discardedTestCount == 3)
    }

    @Test func `public full-list result reports discarded sessions`() async throws {
        let result = try await screenClient().listAllTestsResult(candidateEmail: "malformed@example.com")

        #expect(result.tests.map(\.id) == [1, 2])
        #expect(result.discardedCount == 1)
        #expect(result.diagnostic != nil)
    }

    @Test(arguments: [0, -1, Int.min])
    func `question decoder rejects nonpositive identity`(id: Int) throws {
        let data = try JSONSerialization.data(withJSONObject: ["id": id])
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ScreenTestQuestion.self, from: data)
        }
    }

    @Test func `session field type mismatches discard the record`() throws {
        let data = Data(
            #"{"tests":[{"id":1,"candidate_email":42},{"id":2,"candidate_email":"ada@example.com"}]}"#.utf8
        )

        let page = try JSONDecoder().decode(ScreenTestsPage.self, from: data)

        #expect(page.tests.map(\.id) == [2])
        #expect(page.discardedTestCount == 1)
    }

    @Test func `malformed report fields do not disappear as missing data`() {
        let data = Data(#"{"score":"perfect","warnings":[]}"#.utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ScreenReport.self, from: data)
        }
    }

    @Test func `malformed report warnings do not truncate silently`() {
        let data = Data(#"{"warnings":["valid",42]}"#.utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ScreenReport.self, from: data)
        }
    }
}

@Suite("Screen report warning identity")
struct ScreenReportWarningIdentityTests {
    @Test
    func `duplicate warning text retains distinct occurrence identities`() {
        let rows = ScreenTestDetailView.warningRows(["Window changed", "Window changed", "Paste detected"])

        #expect(rows.map(\.id) == [0, 1, 2])
        #expect(rows.map(\.text) == ["Window changed", "Window changed", "Paste detected"])
    }
}
