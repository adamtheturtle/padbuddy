//
//  PadHistoryPlayback+Preview.swift
//  coderpad
//
//  The History playback preview, split from PadHistoryPlayback.swift to keep
//  that file under the length lint.
//

import SwiftUI

#Preview {
    func entry(_ id: String, _ author: String, _ text: String, at time: Int64) -> PadHistoryEntry {
        PadHistoryEntry(id: id, author: author, operations: [.insert(text)], timestamp: time)
    }

    return HistoryPlaybackView(
        histories: [
            PadFileHistory(id: "main", title: "main.py", language: "python", history: PadHistory(entries: [
                entry("a", "CoderPad", "# Template\n", at: 500),
                entry("b", "4503601411610331", "def two_sum(nums, target):\n", at: 1000),
                entry("c", "4503601411610331", "    seen = {}\n", at: 90000),
                entry("d", "9988776655443322", "    for i, n in enumerate(nums):\n", at: 200_000)
            ])),
            PadFileHistory(id: "util", title: "util.py", language: "python", history: PadHistory(entries: [
                entry("e", "-MockUploadHistory01", "import math\n", at: 140_000)
            ]))
        ],
        events: [],
        dark: false
    )
    .padding()
    .frame(width: 480)
}
