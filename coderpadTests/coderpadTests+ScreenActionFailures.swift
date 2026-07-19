//
//  coderpadTests+ScreenActionFailures.swift
//  coderpadTests
//

@testable import CoderPad
import Foundation
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
    @Test func `failed refetch retains the row as cancelled`() {
        let current = ScreenTestSession(id: 42, status: "waiting", candidateName: "Ada")
        let reconciled = ScreenCancelReconciliation.session(current: current, fresh: nil)
        #expect(reconciled.id == current.id)
        #expect(reconciled.candidateName == current.candidateName)
        #expect(reconciled.status == "cancelled")
    }

    @Test func `successful refetch replaces the local row`() {
        let current = ScreenTestSession(id: 42, status: "waiting")
        let fresh = ScreenTestSession(id: 42, status: "aborted", candidateName: "Fresh")
        #expect(ScreenCancelReconciliation.session(current: current, fresh: fresh) == fresh)
    }
}

@Suite("Screen campaign diagnostics")
struct ScreenCampaignDiagnosticTests {
    @Test func `tolerant campaign list counts discarded records`() throws {
        let data = Data(
            #"""
            [
              {"id":1,"name":"Valid"}, {"id":2,"name":"   "}, {"name":"Missing id"},
              {"id":0,"name":"Zero"}, {"id":-1,"name":"Negative"}
            ]
            """#.utf8
        )
        let list = try JSONDecoder().decode(TolerantScreenList<ScreenCampaign>.self, from: data)
        #expect(list.elements.map(\.id) == [1])
        #expect(list.discardedCount == 4)
        #expect(ScreenCampaignListResult(campaigns: list.elements, discardedCount: 4).diagnostic != nil)
    }

    @Test func `clean campaign list has no diagnostic`() {
        #expect(ScreenCampaignListResult(campaigns: [], discardedCount: 0).diagnostic == nil)
    }
}

@Suite("Screen session diagnostics")
struct ScreenSessionDiagnosticTests {
    @Test func `page counts discarded candidate sessions`() throws {
        let data = Data(#"{"tests":[{"id":1,"status":"waiting"},{"status":"waiting"}],"pagination":null}"#.utf8)
        let page = try JSONDecoder().decode(ScreenTestsPage.self, from: data)
        #expect(page.tests.map(\.id) == [1])
        #expect(page.discardedTestCount == 1)
        #expect(ScreenTestListResult(tests: page.tests, discardedCount: 1).diagnostic != nil)
    }
}
