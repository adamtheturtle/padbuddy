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
    /// A compact stand-in for "are these the same histories".
    ///
    /// Keying the rebuild on `histories` itself made SwiftUI Equatable-compare the
    /// array on every body pass — and each element carries a snapshot per revision,
    /// each holding the full accumulated code at that point, so a long session meant
    /// walking megabytes of text just to notice a refresh (#2462). Each file's id,
    /// snapshot count, and last entry id together change whenever a refresh brings
    /// anything new, without touching the contents.
    var historiesSignature: String {
        histories.lazy
            .map { "\($0.id):\($0.snapshots.count):\($0.snapshots.last?.entry.id ?? "")" }
            .joined(separator: "\u{1}")
    }

    /// The same trick for the events feed, which drives the cached run markers
    /// (#2090): comparing `[PadEvent]` itself would walk every event's strings on
    /// each body pass, and the feed only ever grows or is replaced wholesale.
    var eventsSignature: String {
        "\(events.count)\u{1}\(events.first?.id ?? "")\u{1}\(events.last?.id ?? "")"
    }

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
