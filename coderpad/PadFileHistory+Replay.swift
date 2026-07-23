//
//  PadFileHistory+Replay.swift
//  coderpad
//

import BuddyAppKit
import Foundation

nonisolated struct PadHistoryReplayResult {
    let contents: String
    let changeLine: Int
    let cursorOffset: Int
    let cursorLine: Int
}

nonisolated struct PadHistorySnapshot: Identifiable, Hashable {
    var id: String {
        "\(index)-\(entry.id)"
    }

    let index: Int
    let entry: PadHistoryEntry
    let changeLine: Int
    let cursorOffset: Int
    let cursorLine: Int
}

extension PadFileHistory {
    /// A full document is retained only periodically. Intermediate snapshots keep
    /// their OT entry and replay from the nearest checkpoint on demand, changing
    /// resident history from one document copy per edit to about one per 128 edits.
    nonisolated static let checkpointInterval = 128

    /// Materializes one document state from the closest retained checkpoint.
    /// At most `checkpointInterval - 1` OT entries are replayed.
    nonisolated func contents(at snapshotIndex: Int) -> String? {
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
    ) -> PadHistoryReplayResult {
        let source = Array(contents.utf16)
        var cursor = 0
        var updated: [UInt16] = []
        var editOffset: Int?
        var caretOffset: Int?
        func append(_ units: some Sequence<UInt16>) {
            updated.append(contentsOf: units)
        }
        for operation in entry.operations {
            switch operation {
            case let .insert(text):
                editOffset = editOffset ?? updated.count
                append(text.utf16)
                caretOffset = updated.count

            case let .retain(requested):
                let count = min(max(0, requested), source.count - cursor)
                append(source[cursor ..< cursor + count])
                cursor += count

            case let .delete(requested):
                editOffset = editOffset ?? updated.count
                cursor += min(max(0, requested), source.count - cursor)
                caretOffset = updated.count
            }
        }
        append(source[cursor...])
        let cursorOffset = min(caretOffset ?? editOffset ?? 0, updated.count)
        let lineOffset = min(editOffset ?? cursorOffset, updated.count)
        let changeLine = updated[..<lineOffset].reduce(into: 0) { count, unit in
            if unit == 10 { count += 1 }
        }
        let cursorLine = updated[..<cursorOffset].reduce(into: 0) { count, unit in
            if unit == 10 { count += 1 }
        }
        return PadHistoryReplayResult(
            contents: String(decoding: updated, as: UTF16.self),
            changeLine: changeLine,
            cursorOffset: cursorOffset,
            cursorLine: cursorLine
        )
    }
}
