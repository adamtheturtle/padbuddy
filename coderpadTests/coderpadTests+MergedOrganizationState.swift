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
}
