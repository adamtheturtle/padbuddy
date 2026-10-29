import Foundation
@testable import PadBuddy
import Testing

@Suite("Bounded history construction")
struct PadHistoryConstructionLimitTests {
    private func entry(_ id: Int, operations: [PadHistoryOperation]) -> PadHistoryEntry {
        PadHistoryEntry(id: "e\(id)", author: "Ada", operations: operations, timestamp: Int64(id))
    }

    @Test func `overflow stops at the entry boundary without replaying an overflow prefix`() {
        let history = PadHistory(entries: (0 ... PadFileHistory.maxSnapshotEntries).map {
            entry($0, operations: [])
        })
        let file = PadFileHistory(id: "f", title: "main", language: nil, history: history)
        #expect(file.snapshots.count == PadFileHistory.maxSnapshotEntries)
        #expect(file.startingContents.isEmpty)
        #expect(file.wasTruncated)
        #expect(file.history.entries.count == file.snapshots.count)
    }

    @Test func `oversized inserts and operation arrays are rejected before replay`() {
        let oversized = String(repeating: "x", count: PadHistoryBuild.maximumInsertBytes + 1)
        let tooManyOperations = Array(
            repeating: PadHistoryOperation.retain(0), count: PadHistoryBuild.maximumOperationsPerEntry + 1
        )
        for operations in [[.insert(oversized)], tooManyOperations] {
            let built = PadHistoryBuild(history: PadHistory(entries: [entry(0, operations: operations)]))
            #expect(built.snapshots.isEmpty)
            #expect(built.wasTruncated)
        }
    }

    @Test func `document growth is checked before a second insert is materialized`() {
        let text = String(repeating: "x", count: PadHistoryBuild.maximumDocumentUnits)
        let built = PadHistoryBuild(history: PadHistory(entries: [
            entry(0, operations: [.insert(text)]), entry(1, operations: [.insert("x")])
        ]))
        #expect(built.snapshots.count == 1)
        #expect(built.wasTruncated)
    }

    @Test func `storage and work limits preserve checkpoint coverage for every retained snapshot`() {
        let history = PadHistory(entries: (0 ..< 1000).map { entry($0, operations: [.insert("line\n")]) })
        for built in [PadHistoryBuild(history: history, byteLimit: 30000),
                      PadHistoryBuild(history: history, workLimit: 10000)] {
            #expect(built.wasTruncated)
            #expect(built.retainedBytes <= 30000)
            for snapshot in built.snapshots {
                let checkpoint = built.checkpoints.last { $0.snapshotIndex <= snapshot.index }
                #expect(snapshot.index - (checkpoint?.snapshotIndex ?? -1) < PadFileHistory.checkpointInterval)
            }
        }
    }
}
