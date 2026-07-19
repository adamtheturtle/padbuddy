//
//  PadFileHistory+Replay.swift
//  coderpad
//

import BuddyAppKit
import Foundation

extension PadFileHistory {
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
