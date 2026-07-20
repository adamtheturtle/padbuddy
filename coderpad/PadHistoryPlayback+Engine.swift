//
//  PadHistoryPlayback+Engine.swift
//  coderpad
//
//  The playback engine behind the History card's session replay — position
//  stepping, the real-pace play loop, and the timeline rebuild that follows a
//  history refresh. Split from PadHistoryPlayback.swift to keep it within the
//  lint length limit.
//

import SwiftUI

extension HistoryPlaybackView {
    func setPosition(_ index: Int) {
        position = min(max(0, index), max(0, timeline.items.count - 1))
    }

    /// A user-initiated jump - scrubbing, stepping, or a lane click - goes back
    /// to following the file being edited at the playhead. Only the play loop's
    /// automatic advance keeps a manually picked file in view (#1877).
    func userSetPosition(_ index: Int) {
        manualFileID = nil
        setPosition(index)
    }

    func togglePlayback() {
        if isPlaying {
            stopPlayback()
        } else {
            startPlayback()
        }
    }

    /// Replays edits at the pace they actually happened, divided by the chosen
    /// speed, reading `position` fresh each step so scrubbing mid-play just
    /// moves the replay rather than fighting it.
    func startPlayback() {
        stopPlayback()
        guard timeline.items.count > 1 else { return }

        if position >= timeline.items.count - 1 {
            setPosition(0)
        }
        isPlaying = true
        playbackGeneration &+= 1
        let generation = playbackGeneration
        playbackTask = Task {
            while !Task.isCancelled, position < timeline.items.count - 1 {
                let advance = Self.playbackAdvance(
                    timeline: timeline, from: position, speed: playbackSpeed
                )
                do {
                    try await Task.sleep(for: .seconds(advance.delay))
                } catch {
                    break
                }
                guard !Task.isCancelled else { break }

                setPosition(advance.position)
            }
            // Only this session may switch its own indicator off: a cancelled
            // older task reaching here must not turn off the UI of the session
            // that replaced it (#1168).
            if generation == playbackGeneration {
                isPlaying = false
            }
        }
    }

    /// The next rendered playhead and its delay. Edits closer together than one
    /// display frame are coalesced into that frame instead of forcing a complete
    /// code layout for every same-millisecond operation (#2895). A real pause is
    /// never crossed while coalescing, so session timing remains faithful.
    nonisolated static func playbackAdvance(
        timeline: PadPlaybackTimeline, from position: Int, speed: Double
    ) -> (position: Int, delay: Double) {
        guard position + 1 < timeline.items.count else { return (position, 0) }

        let safeSpeed = max(speed, 0.01)
        var target = position + 1
        var delay = min(timeline.gapSeconds(after: position), maxPlaybackGap) / safeSpeed
        while target + 1 < timeline.items.count {
            let following = min(timeline.gapSeconds(after: target), maxPlaybackGap) / safeSpeed
            guard delay + following <= minPlaybackStep else { break }

            target += 1
            delay += following
        }
        return (target, max(delay, minPlaybackStep))
    }

    func stopPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
        isPlaying = false
    }

    func rebuildTimeline() {
        // Replacing the timeline under a running replay would let the old task
        // keep advancing the new timeline with stale gaps and a stale position,
        // wherever the rebuild came from (#1167, #1868).
        stopPlayback()

        // A background refresh replacing the histories keeps the playhead where
        // it was, except "showing the latest edit" tracks the new latest. The
        // kept position is resolved by its *moment*, not its integer offset: a
        // refresh that inserts or deletes edits before the playhead would leave
        // the old index pointing at a different time and file (#1166).
        let wasAtEnd = position >= timeline.items.count - 1
        let anchor = timeline.items.indices.contains(position) ? timeline.items[position].timestamp : nil

        // Merging and sorting every snapshot is O(n log n) over the whole
        // session; done off the main actor so a large history refresh can't
        // stall scrolling (#1870).
        rebuildGeneration &+= 1
        let generation = rebuildGeneration
        let histories = histories
        Task {
            let rebuilt = await Task.detached { PadPlaybackTimeline(histories: histories) }.value
            // A slower rebuild of an older histories value must not overwrite a
            // newer one (#1870).
            guard generation == rebuildGeneration else { return }

            timeline = rebuilt
            // The markers map event dates onto the new timeline's extent (#2090).
            runMarkers = Self.runMarkers(events: events, timeline: rebuilt)
            let last = max(0, rebuilt.items.count - 1)
            if wasAtEnd {
                position = last
            } else if let anchor {
                position = rebuilt.items.lastIndex(where: { $0.timestamp <= anchor }) ?? 0
            } else {
                position = min(position, last)
            }
        }
    }
}
