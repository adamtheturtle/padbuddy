//
//  PadBuddyTests+PadHistorySnapshotBudget.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Pad history snapshot budget (#4762)")
struct PadHistorySnapshotBudgetTests {
    private func history(entryCount: Int) -> PadHistory {
        PadHistory(entries: (0 ..< entryCount).map {
            PadHistoryEntry(id: "e\($0)", author: "a", operations: [.insert("line \($0)\n")],
                            timestamp: Int64($0))
        })
    }

    @Test func `every entry becomes a snapshot`() {
        let file = PadFileHistory(id: "f", title: "main.py", language: "python",
                                  history: history(entryCount: 300))

        // The byte budget bounds checkpoint storage. It used to `break` the whole loop, so
        // crossing it dropped the *newest* snapshots: the scrubber ended partway through
        // the session and the code at the end of the interview was simply absent.
        #expect(file.snapshots.count == 300)
        #expect(file.snapshots.map(\.index) == Array(0 ..< 300))
    }

    @Test func `checkpoints are taken at the interval`() {
        let file = PadFileHistory(id: "f", title: "main.py", language: "python",
                                  history: history(entryCount: 300))

        #expect(file.checkpoints.map(\.snapshotIndex) == [0, PadFileHistory.checkpointInterval,
                                                          PadFileHistory.checkpointInterval * 2])
    }

    @Test func `a history within the entry cap keeps all of it`() {
        let file = PadFileHistory(id: "f", title: "main.py", language: "python",
                                  history: history(entryCount: 20))

        #expect(file.snapshots.count == 20)
        #expect(!file.checkpoints.isEmpty)
        #expect(file.startingContents.isEmpty)
    }
}
