//
//  PadBuddyTests+PadDestructiveMutationGate.swift
//  PadBuddyTests
//

@testable import PadBuddy
import Testing

@Suite("Pad destructive mutation gate")
struct PadDestructiveMutationGateTests {
    @Test
    func `end claim excludes deletion until it finishes`() {
        var gate = PadDestructiveMutationGate()

        let ending = gate.begin(.ending)
        let deletionWhileEnding = gate.begin(.deleting)
        #expect(ending)
        #expect(!deletionWhileEnding)
        gate.finish(.ending)
        let deletionAfterEnding = gate.begin(.deleting)
        #expect(deletionAfterEnding)
    }

    @Test
    func `deletion claim excludes ending and only its owner releases it`() {
        var gate = PadDestructiveMutationGate()

        let deletion = gate.begin(.deleting)
        let endingWhileDeleting = gate.begin(.ending)
        #expect(deletion)
        #expect(!endingWhileDeleting)
        gate.finish(.ending)
        #expect(gate.isActive)
        gate.finish(.deleting)
        #expect(!gate.isActive)
    }
}
