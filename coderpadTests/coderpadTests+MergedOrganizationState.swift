//
//  coderpadTests+MergedOrganizationState.swift
//  coderpadTests
//

@testable import CoderPad
import Foundation
import Testing

@Suite("Merged organization state")
struct MergedOrganizationStateTests {
    @Test
    func `only the latest reload generation may publish`() {
        #expect(MergedOrganizationView.isCurrentReload(4, current: 4))
        #expect(!MergedOrganizationView.isCurrentReload(3, current: 4))
    }

    @Test
    func `only entries for live eligible accounts survive pruning`() {
        let live = UUID()
        let removed = UUID()
        let entries = [live: "current", removed: "stale"]

        let retained = MergedOrganizationView.retainingEntries(entries, for: [live])

        #expect(retained == [live: "current"])
        #expect(MergedOrganizationView.retainingEntries(entries, for: [:]).isEmpty)
    }

    @Test
    func `results require the same current client identity`() throws {
        let baseURL = try #require(URL(string: "https://example.com"))
        let requested = ClientTaskIdentity(apiKey: "old", baseURL: baseURL)
        let current = ClientTaskIdentity(apiKey: "new", baseURL: baseURL)

        #expect(MergedOrganizationView.isCurrentTarget(requested, current: requested))
        #expect(!MergedOrganizationView.isCurrentTarget(requested, current: current))
        #expect(!MergedOrganizationView.isCurrentTarget(requested, current: nil))
    }

    @Test
    func `aggregate coverage requires every eligible account and no failures`() {
        let first = UUID()
        let second = UUID()
        let eligible: Set<UUID> = [first, second]

        #expect(MergedOrganizationView.hasCompleteCoverage(
            eligibleIDs: eligible, loadedIDs: eligible, failedIDs: []
        ))
        #expect(!MergedOrganizationView.hasCompleteCoverage(
            eligibleIDs: eligible, loadedIDs: [first], failedIDs: []
        ))
        #expect(!MergedOrganizationView.hasCompleteCoverage(
            eligibleIDs: eligible, loadedIDs: eligible, failedIDs: [second]
        ))
    }

    @Test
    func `resource failure status is inserted and cleared per account`() {
        let account = UUID()
        let other = UUID()

        let failed = MergedOrganizationView.updatingFailures([other], id: account, failed: true)
        #expect(failed == [account, other])
        #expect(MergedOrganizationView.updatingFailures(failed, id: account, failed: false) == [other])
    }
}
