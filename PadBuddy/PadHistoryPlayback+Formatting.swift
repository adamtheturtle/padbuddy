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
    /// Reconcile only names that the history itself identifies. The pad participant
    /// array and history connection IDs share no identifier or guaranteed ordering;
    /// assigning leftover names by position can put the wrong person's name on the
    /// active cursor (#2915). Opaque authors therefore remain color-only until
    /// CoderPad exposes an authoritative mapping (#2922).
    nonisolated static func participantNameMap(authors: [String], names: [String]) -> [String: String] {
        var seen = Set<String>()
        let names = names.compactMap { raw -> String? in
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(name.lowercased()).inserted else { return nil }

            return name
        }
        var result: [String: String] = [:]
        for author in authors {
            guard let displayed = PadPlaybackAuthors.displayName(author),
                  let matchingName = names.first(where: {
                      $0.caseInsensitiveCompare(displayed) == .orderedSame
                  }) else { continue }

            result[author] = matchingName
        }
        return result
    }

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
        "\(events.count)\u{1}\(events.first?.identity ?? "")\u{1}\(events.last?.identity ?? "")"
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
}
