//
//  coderpadTests+PadDestructiveMutationGate.swift
//  coderpadTests
//

@testable import CoderPad
import Testing

@Suite("Pad destructive mutation gate")
struct PadDestructiveMutationGateTests {
    @Test
    func `end claim excludes deletion until it finishes`() {
        var gate = PadDestructiveMutationGate()

        #expect(gate.begin(.ending))
        #expect(!gate.begin(.deleting))
        gate.finish(.ending)
        #expect(gate.begin(.deleting))
    }

    @Test
    func `deletion claim excludes ending and only its owner releases it`() {
        var gate = PadDestructiveMutationGate()

        #expect(gate.begin(.deleting))
        #expect(!gate.begin(.ending))
        gate.finish(.ending)
        #expect(gate.isActive)
        gate.finish(.deleting)
        #expect(!gate.isActive)
    }
}
