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
                let gap = min(timeline.gapSeconds(after: position), Self.maxPlaybackGap)
                let delay = max(gap / playbackSpeed, Self.minPlaybackStep)
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    break
                }
                guard !Task.isCancelled else { break }
                setPosition(position + 1)
            }
            // Only this session may switch its own indicator off: a cancelled
            // older task reaching here must not turn off the UI of the session
            // that replaced it (#1168).
            if generation == playbackGeneration {
                isPlaying = false
            }
        }
    }

    func stopPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
        isPlaying = false
    }

    func rebuildTimeline() {
        // A background refresh replacing the histories keeps the playhead where
        // it was, except "showing the latest edit" tracks the new latest. The
        // kept position is resolved by its *moment*, not its integer offset: a
        // refresh that inserts or deletes edits before the playhead would leave
        // the old index pointing at a different time and file (#1166).
        let wasAtEnd = position >= timeline.items.count - 1
        let anchor = timeline.items.indices.contains(position) ? timeline.items[position].timestamp : nil
        timeline = PadPlaybackTimeline(histories: histories)
        let last = max(0, timeline.items.count - 1)
        if wasAtEnd {
            position = last
        } else if let anchor {
            position = timeline.items.lastIndex(where: { $0.timestamp <= anchor }) ?? 0
        } else {
            position = min(position, last)
        }
    }
}
