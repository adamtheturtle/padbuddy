//
//  NetworkMonitorTests.swift
//  BuddyAppKitTests
//

@testable import BuddyAppKit
import Testing

@Suite("Network monitor lifecycle (#1276)")
struct NetworkMonitorTests {
    @Test
    func `only callbacks from the running generation may publish`() {
        #expect(NetworkMonitor.isCurrentCallback(3, currentGeneration: 3, isRunning: true))
        #expect(!NetworkMonitor.isCurrentCallback(2, currentGeneration: 3, isRunning: true))
        #expect(!NetworkMonitor.isCurrentCallback(3, currentGeneration: 3, isRunning: false))
    }
}
