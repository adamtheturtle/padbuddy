//
//  NetworkMonitorTests.swift
//  BuddyAppKitTests
//

@testable import BuddyAppKit
import Testing

@Suite("Network monitor lifecycle (#1276)")
struct NetworkMonitorTests {
    @Test
    func `unknown and unsatisfied paths fail closed`() {
        #expect(NetworkMonitor.offlineState(pathIsSatisfied: nil))
        #expect(NetworkMonitor.offlineState(pathIsSatisfied: false))
        #expect(!NetworkMonitor.offlineState(pathIsSatisfied: true))
    }

    @Test
    func `only callbacks from the running generation may publish`() {
        #expect(NetworkMonitor.isCurrentCallback(3, currentGeneration: 3, isRunning: true))
        #expect(!NetworkMonitor.isCurrentCallback(2, currentGeneration: 3, isRunning: true))
        #expect(!NetworkMonitor.isCurrentCallback(3, currentGeneration: 3, isRunning: false))
    }

    @Test
    func `recovery is immediate while loss is delayed`() {
        #expect(NetworkMonitor.pathTransition(isCurrentlyOffline: true, pathIsSatisfied: true) == .publishOnline)
        #expect(NetworkMonitor.pathTransition(isCurrentlyOffline: false, pathIsSatisfied: false) == .scheduleOffline)
        #expect(NetworkMonitor.pathTransition(isCurrentlyOffline: false, pathIsSatisfied: true) == .publishOnline)
        #expect(NetworkMonitor.pathTransition(isCurrentlyOffline: true, pathIsSatisfied: false) == .noChange)
    }
}
