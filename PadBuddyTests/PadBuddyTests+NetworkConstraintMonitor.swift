//
//  PadBuddyTests+NetworkConstraintMonitor.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Low Data Mode monitoring (#4571, #4572, #4573)", .serialized)
@MainActor
struct NetworkConstraintMonitorTests {
    @Test func `the constraint is unknown before any path arrives`() {
        let monitor = NetworkConstraintMonitor.shared
        monitor.stop()

        #expect(monitor.state == .unknown)
        // The old default reported "not constrained" here, so launch-time work could
        // pick an unconstrained policy for a path nobody had looked at yet.
        #expect(!monitor.hasResolvedPath)
        #expect(!monitor.isConstrained)
    }

    @Test func `starting twice keeps a single monitor`() {
        let monitor = NetworkConstraintMonitor.shared
        monitor.stop()

        monitor.start()
        monitor.start()

        monitor.stop()
        #expect(monitor.state == .unknown)
    }

    @Test func `stopping is idempotent and returns to unknown`() {
        let monitor = NetworkConstraintMonitor.shared
        monitor.start()

        monitor.stop()
        monitor.stop()

        #expect(monitor.state == .unknown)
    }

    @Test func `a stopped monitor can be started again`() {
        let monitor = NetworkConstraintMonitor.shared
        monitor.start()
        monitor.stop()

        monitor.start()

        monitor.stop()
        #expect(monitor.state == .unknown)
    }
}
