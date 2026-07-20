//
//  PadFileHistory+Replay.swift
//  coderpad
//

import BuddyAppKit
import Foundation

extension PadFileHistory {
    /// A full document is retained only periodically. Intermediate snapshots keep
    /// their OT entry and replay from the nearest checkpoint on demand, changing
    /// resident history from one document copy per edit to about one per 128 edits.
    nonisolated static let checkpointInterval = 128

    /// Materializes one document state from the closest retained checkpoint.
    /// At most `checkpointInterval - 1` OT entries are replayed.
    func contents(at snapshotIndex: Int) -> String? {
        guard snapshots.indices.contains(snapshotIndex) else { return nil }

        let checkpoint = checkpoints.last { $0.snapshotIndex <= snapshotIndex }
        var contents = checkpoint?.contents ?? startingContents
        let first = (checkpoint?.snapshotIndex ?? -1) + 1
        guard first <= snapshotIndex else { return contents }

        for index in first ... snapshotIndex {
            contents = snapshots[index].entry.applying(to: contents)
        }
        return contents
    }

    /// Bytes retained specifically for replayable full-document state.
    var retainedSnapshotContentBytes: Int {
        startingContents.utf8.count + checkpoints.reduce(0) { $0 + $1.contents.utf8.count }
    }

    /// Replays an OT entry and counts its destination line while the UTF-16 output
    /// is already being built, avoiding a second prefix scan per snapshot (#2000).
    nonisolated static func replay(
        _ entry: PadHistoryEntry,
        on contents: String
    ) -> (contents: String, changeLine: Int) {
        var offset = 0
        for operation in entry.operations {
            guard case let .retain(count) = operation else { break }

            let (sum, overflow) = offset.addingReportingOverflow(count)
            offset = overflow ? (count >= 0 ? .max : .min) : sum
        }

        let source = Array(contents.utf16)
        let target = max(0, offset)
        var cursor = 0
        var updated: [UInt16] = []
        var changeLine = 0
        func append(_ units: some Sequence<UInt16>) {
            for unit in units {
                updated.append(unit)
                if updated.count <= target, unit == 10 { changeLine += 1 }
            }
        }
        for operation in entry.operations {
            switch operation {
            case let .insert(text):
                append(text.utf16)

            case let .retain(requested):
                let count = min(max(0, requested), source.count - cursor)
                append(source[cursor ..< cursor + count])
                cursor += count

            case let .delete(requested):
                cursor += min(max(0, requested), source.count - cursor)
            }
        }
        append(source[cursor...])
        return (String(decoding: updated, as: UTF16.self), changeLine)
    }
}
