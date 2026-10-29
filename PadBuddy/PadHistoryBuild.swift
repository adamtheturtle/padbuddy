import Foundation

/// Validates work and output size before applying any remote OT entry.
nonisolated struct PadHistoryBuild {
    static let maximumOperationsPerEntry = 2048
    static let maximumOperations = 100_000
    static let maximumDocumentUnits = 1_000_000
    static let maximumInsertBytes = 1_000_000
    static let maximumReplayWork = 100_000_000

    let snapshots: [PadHistorySnapshot]
    let checkpoints: [PadFileHistory.Checkpoint]
    let wasTruncated: Bool
    let retainedBytes: Int

    /// The loop owns the shared storage/work budget and keeps every retained snapshot replayable.
    init(history: PadHistory, byteLimit: Int = PadFileHistory.maxSnapshotBytes,
         workLimit: Int = Self.maximumReplayWork, now: Date = .now) {
        let byteLimit = min(max(0, byteLimit), PadFileHistory.maxSnapshotBytes)
        let workLimit = min(max(0, workLimit), Self.maximumReplayWork)
        var built: [PadHistorySnapshot] = []
        var checkpoints: [PadFileHistory.Checkpoint] = []
        var contents = ""
        var retained = 0, operations = 0, work = 0
        var previousTimestamp: Int64?
        for entry in history.entries.prefix(PadFileHistory.maxSnapshotEntries) {
            guard let timestamp = PadHistoryTimestampPolicy.admitted(
                entry.timestamp, after: previousTimestamp, now: now
            ), operations + entry.operations.count <= Self.maximumOperations,
            let cost = Self.cost(entry, sourceUnits: contents.utf16.count) else { break }

            let nextWork = contents.utf16.count + cost.outputUnits + entry.operations.count
            guard nextWork <= workLimit - work, cost.bytes <= byteLimit - retained else { break }

            let replay = PadFileHistory.replay(entry, on: contents)
            let needsCheckpoint = built.count.isMultiple(of: PadFileHistory.checkpointInterval)
            let checkpointBytes = needsCheckpoint ? replay.contents.utf8.count : 0
            guard checkpointBytes <= byteLimit - retained - cost.bytes else { break }

            previousTimestamp = timestamp
            contents = replay.contents
            operations += entry.operations.count
            work += nextWork
            retained += cost.bytes + checkpointBytes
            if needsCheckpoint {
                checkpoints.append(.init(snapshotIndex: built.count, contents: contents))
            }
            built.append(PadHistorySnapshot(index: built.count, entry: entry,
                                            changeLine: replay.changeLine,
                                            cursorOffset: replay.cursorOffset, cursorLine: replay.cursorLine))
        }
        snapshots = built
        self.checkpoints = checkpoints
        wasTruncated = built.count != history.entries.count
        retainedBytes = retained
    }

    private static func cost(_ entry: PadHistoryEntry, sourceUnits: Int) -> (bytes: Int, outputUnits: Int)? {
        guard entry.operations.count <= maximumOperationsPerEntry,
              entry.id.utf8.prefix(1025).count <= 1024,
              entry.author.utf8.prefix(2049).count <= 2048 else { return nil }

        var bytes = 128 + entry.id.utf8.count + entry.author.utf8.count + entry.operations.count * 16
        var cursor = 0, output = 0
        for operation in entry.operations {
            switch operation {
            case let .insert(text):
                guard text.utf8.prefix(maximumInsertBytes + 1).count <= maximumInsertBytes else { return nil }

                output += text.utf16.count
                bytes += text.utf8.count

            case let .retain(requested):
                let count = min(max(0, requested), sourceUnits - cursor)
                cursor += count
                output += count

            case let .delete(requested):
                cursor += min(max(0, requested), sourceUnits - cursor)
            }
            guard output <= maximumDocumentUnits else { return nil }
        }
        output += sourceUnits - cursor
        return output <= maximumDocumentUnits ? (bytes, output) : nil
    }
}
