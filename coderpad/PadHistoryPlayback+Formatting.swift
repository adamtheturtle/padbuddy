//
//  PadHistoryPlayback+Formatting.swift
//  coderpad
//
//  The playback scrubber's time and date labels, with their format styles built
//  once. Split from PadHistoryPlayback.swift to keep that file under the
//  file-length limit.
//

import Foundation
import SwiftUI

extension HistoryPlaybackView {
    /// The two scrubber styles, built once. `timeText` runs twice per render — the
    /// elapsed and total labels — inside a scrubber that re-renders on every timeline
    /// tick and every drag frame, so constructing the style per call put formatter
    /// setup on an interactive per-frame path (#2432). Matches the treatment
    /// `historyDateStyle` already had (#1884).
    static let shortTimeStyle = Duration.TimeFormatStyle(pattern: .minuteSecond)
    static let longTimeStyle = Duration.TimeFormatStyle(pattern: .hourMinuteSecond)

    func timeText(_ seconds: Double) -> String {
        let style = timeline.durationSeconds >= 3600 ? Self.longTimeStyle : Self.shortTimeStyle
        return Duration.seconds(seconds).formatted(style)
    }

    /// One shared style instance rather than a fresh one per body pass (#1884).
    static let historyDateStyle = Date.FormatStyle(date: .long, time: .shortened)

    func historyDate(_ milliseconds: Int64) -> String {
        Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
            .formatted(Self.historyDateStyle)
    }
}
