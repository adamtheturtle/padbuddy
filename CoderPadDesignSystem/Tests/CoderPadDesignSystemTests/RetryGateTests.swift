//
//  RetryGateTests.swift
//  CoderPadDesignSystemTests
//

@testable import CoderPadDesignSystem
import Testing

@Suite("Filterable list retry admission")
struct RetryGateTests {
    @Test
    func `a retry is rejected while another retry is running`() {
        var gate = RetryGate()

        let first = gate.begin()
        let overlapping = gate.begin()
        #expect(first)
        #expect(!overlapping)
        #expect(gate.isRunning)
    }

    @Test
    func `finishing permits the next retry`() {
        var gate = RetryGate()

        let first = gate.begin()
        #expect(first)
        gate.finish()

        #expect(!gate.isRunning)
        let next = gate.begin()
        #expect(next)
    }
}
