//
//  PadBuddyTests+ProvisioningRevisionRollover.swift
//  PadBuddyTests
//

@testable import PadBuddy
import Testing

@Suite("Provisioning revision rollover")
struct ProvisioningRevisionRolloverTests {
    @Test func `terminal revision explicitly rolls the counter into a new epoch`() {
        let terminal = maxProvisioningRevision

        #expect(nextWatchProvisioningRevision(after: terminal - 1) == terminal)
        #expect(shouldApplyWatchProvisioningRevision(terminal, latest: terminal - 1))
        #expect(nextWatchProvisioningRevision(after: terminal) == 1)
        #expect(shouldApplyWatchProvisioningRevision(1, latest: terminal))
    }
}
