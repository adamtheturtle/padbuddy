//
//  PadBuddyTests+ProvisioningRevisionRollover.swift
//  PadBuddyTests
//

@testable import PadBuddy
import Testing

@Suite("Provisioning revision rollover")
struct ProvisioningRevisionRolloverTests {
    @Test func `terminal revision rolls forward without accepting delayed old values`() {
        let terminal = maxProvisioningRevision

        #expect(nextWatchProvisioningRevision(after: terminal - 1) == terminal)
        #expect(shouldApplyWatchProvisioningRevision(terminal, latest: terminal - 1))
        #expect(nextWatchProvisioningRevision(after: terminal) == 1)
        #expect(shouldApplyWatchProvisioningRevision(1, latest: terminal))
        #expect(!shouldApplyWatchProvisioningRevision(terminal, latest: 1))
        #expect(!shouldApplyWatchProvisioningRevision(terminal - 1, latest: 1))
    }
}
