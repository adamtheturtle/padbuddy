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
                entry("b", "Polly Sherman", "def two_sum(nums, target):\n", at: 1000),
                entry("c", "Polly Sherman", "    seen = {}\n", at: 90000),
                entry("d", "Garrett Wang", "    for i, n in enumerate(nums):\n", at: 200_000)
            ])),
            PadFileHistory(id: "util", title: "util.py", language: "python", history: PadHistory(entries: [
                entry("e", "Garrett Wang", "import math\n", at: 140_000)
            ]))
        ],
        events: [],
        dark: false
    )
    .padding()
    .frame(width: 480)
}
