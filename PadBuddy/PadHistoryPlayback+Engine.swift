//
//  PadHistoryPlayback+Engine.swift
//  coderpad
//
//  The playback engine behind the History card's session replay — position
//  stepping, the real-pace play loop, and the timeline rebuild that follows a
//  history refresh. Split from PadHistoryPlayback.swift to keep it within the
//  lint length limit.
//

import Foundation
import SwiftUI

private struct PreparedPlaybackCode {
    let fileID: String
    let snapshotIndex: Int
    let contents: String
    let language: String?
    let focusLine: Int
    let cursorOffset: Int?
}

struct PreparedPlaybackWindow {
    let contents: String
    let focusLine: Int
    let cursorOffset: Int?
}

private struct PreparedPlaybackFrame {
    let code: PreparedPlaybackCode
    let highlightedText: AttributedString?
    let dark: Bool
}

extension HistoryPlaybackView {
    func setPosition(_ index: Int) {
        position = min(max(0, index), max(0, timeline.items.count - 1))
    }

    /// A user-initiated jump - scrubbing, stepping, or a lane click - goes back
    /// to following the file being edited at the playhead. Only the play loop's
    /// automatic advance keeps a manually picked file in view (#1877).
    func userSetPosition(_ index: Int) {
        stopPlayback()
        groupedEditCount = 0
        manualFileID = nil
        setPosition(index)
    }

    func userStepPosition(by delta: Int) {
        groupedEditCount = 0
        manualFileID = nil
        if isPlaying {
            playbackSeekGeneration &+= 1
            setPosition(position + delta * Self.playingStepJump)
            let generation = playbackGeneration
            let seekGeneration = playbackSeekGeneration
            Task {
                await prepareFrame(at: position, generation: generation, seekGeneration: seekGeneration)
            }
        } else {
            setPosition(position + delta)
        }
    }

    func togglePlayback() {
        if isPlaying {
            stopPlayback()
        } else {
            startPlayback()
        }
    }

    /// Replays edits at the pace they actually happened, reading `position`
    /// fresh each step so scrubbing mid-play just moves the replay rather than
    /// fighting it.
    func startPlayback() {
        stopPlayback()
        guard timeline.items.count > 1 else { return }

        let startPosition = position >= timeline.items.count - 1 ? 0 : position
        isPlaying = true
        playbackGeneration &+= 1
        let generation = playbackGeneration
        playbackTask = Task {
            if startPosition != position {
                await prepareFrame(
                    at: startPosition,
                    generation: generation,
                    seekGeneration: playbackSeekGeneration
                )
                guard !Task.isCancelled, generation == playbackGeneration else { return }

                setPosition(startPosition)
            } else {
                await prepareFrame(
                    at: position,
                    generation: generation,
                    seekGeneration: playbackSeekGeneration
                )
            }

            while !Task.isCancelled, position < timeline.items.count - 1 {
                let seekGeneration = playbackSeekGeneration
                let advance = Self.playbackAdvance(timeline: timeline, from: position)
                async let slept: Void = Task.sleep(for: .seconds(advance.delay))
                let prepared = await frame(at: advance.position)
                do {
                    try await slept
                } catch {
                    break
                }
                guard !Task.isCancelled, generation == playbackGeneration else { break }
                guard seekGeneration == playbackSeekGeneration else { continue }

                publishPreparedFrame(prepared)
                groupedEditCount = max(0, advance.position - position - 1)
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
        timeline: PadPlaybackTimeline, from position: Int
    ) -> (position: Int, delay: Double) {
        guard position + 1 < timeline.items.count else { return (position, 0) }

        var target = position + 1
        var delay = min(timeline.gapSeconds(after: position), maxPlaybackGap)
        while target + 1 < timeline.items.count {
            let following = min(timeline.gapSeconds(after: target), maxPlaybackGap)
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

    /// Materialize and highlight a bounded window around the future playhead.
    /// Playback keeps the visible context small so generated files can still move
    /// through the timeline without making SwiftUI lay out megabytes of source.
    private func frame(at position: Int) async -> PreparedPlaybackFrame? {
        guard let code = await playbackCode(at: position) else { return nil }

        let highlighted = await SyntaxHighlighter.highlight(
            code.contents, language: code.language, dark: dark
        )
        return PreparedPlaybackFrame(code: code, highlightedText: highlighted, dark: dark)
    }

    private func prepareFrame(at position: Int, generation: Int, seekGeneration: Int) async {
        guard let code = await playbackCode(at: position) else {
            guard !Task.isCancelled, generation == playbackGeneration,
                  seekGeneration == playbackSeekGeneration else { return }

            publishPreparedFrame(nil)
            return
        }
        guard !Task.isCancelled, generation == playbackGeneration,
              seekGeneration == playbackSeekGeneration else { return }

        // Publish the clipped playback window before syntax highlighting finishes,
        // so starting playback after scrubbing never waits on Highlightr to replace
        // a large paused full-file render.
        publishPreparedFrame(PreparedPlaybackFrame(code: code, highlightedText: nil, dark: dark))

        let highlighted = await SyntaxHighlighter.highlight(
            code.contents, language: code.language, dark: dark
        )
        guard !Task.isCancelled, generation == playbackGeneration,
              seekGeneration == playbackSeekGeneration else { return }

        publishPreparedFrame(PreparedPlaybackFrame(code: code, highlightedText: highlighted, dark: dark))
    }

    private func publishPreparedFrame(
        _ prepared: PreparedPlaybackFrame?
    ) {
        preparedHighlightedText = prepared?.highlightedText
        preparedHighlightedContents = prepared?.code.contents
        preparedHighlightedDark = prepared?.dark
        preparedPlaybackFileID = prepared?.code.fileID
        preparedPlaybackSnapshotIndex = prepared?.code.snapshotIndex
        preparedPlaybackContents = prepared?.code.contents
        preparedPlaybackFocusLine = prepared?.code.focusLine
        preparedPlaybackCursorOffset = prepared?.code.cursorOffset
    }

    private func playbackCode(at position: Int) async -> PreparedPlaybackCode? {
        let fileID = manualFileID
            ?? (timeline.items.indices.contains(position) ? timeline.items[position].fileID : nil)
        guard let file = histories.first(where: { $0.id == fileID }) ?? histories.first,
              let snapshotIndex = timeline.snapshotIndex(of: file.id, at: position),
              file.snapshots.indices.contains(snapshotIndex) else { return nil }

        let snapshot = file.snapshots[snapshotIndex]
        return await Task.detached(priority: .userInitiated) {
            guard let contents = file.contents(at: snapshotIndex) else { return nil as PreparedPlaybackCode? }

            let window = Self.playbackWindow(
                contents: contents,
                focusLine: snapshot.cursorLine,
                cursorOffset: snapshot.cursorOffset
            )
            return PreparedPlaybackCode(
                fileID: file.id,
                snapshotIndex: snapshotIndex,
                contents: window.contents,
                language: file.language,
                focusLine: window.focusLine,
                cursorOffset: window.cursorOffset
            )
        }.value
    }

    nonisolated static func playbackWindow(
        contents: String,
        focusLine: Int,
        cursorOffset: Int
    ) -> PreparedPlaybackWindow {
        let contextLines = 80
        let maxUTF16Length = 120_000
        // swiftlint:disable:next legacy_objc_type
        let nsContents = contents as NSString
        let length = nsContents.length
        guard length > 0 else {
            return PreparedPlaybackWindow(contents: contents, focusLine: 0, cursorOffset: 0)
        }

        let lineStarts = CodeLineBreaks.lineStartUTF16Offsets(in: nsContents)

        let clampedFocusLine = min(max(0, focusLine), max(0, lineStarts.count - 1))
        var startLine = max(0, clampedFocusLine - contextLines)
        var endLine = min(lineStarts.count - 1, clampedFocusLine + contextLines)
        var startOffset = lineStarts[startLine]
        var endOffset = endLine + 1 < lineStarts.count ? lineStarts[endLine + 1] : length

        if endOffset - startOffset > maxUTF16Length {
            let center = min(max(cursorOffset, startOffset), endOffset)
            startOffset = max(startOffset, center - maxUTF16Length / 2)
            endOffset = min(endOffset, startOffset + maxUTF16Length)
            startLine = lineStarts.lastIndex(where: { $0 <= startOffset }) ?? startLine
            endLine = lineStarts.lastIndex(where: { $0 < endOffset }) ?? endLine
        }

        let windowRange = NSRange(location: startOffset, length: max(0, endOffset - startOffset))
        let windowContents = nsContents.substring(with: windowRange)
        let adjustedCursor: Int? = if cursorOffset >= startOffset, cursorOffset <= endOffset {
            cursorOffset - startOffset
        } else {
            nil
        }
        // Clamped into the window that was actually produced. `focusLine` and
        // `cursorOffset` are computed independently during replay and can disagree, so
        // re-centring on the cursor above could move `startLine` past
        // `clampedFocusLine` and return a negative focus line — which `HighlightedCode`
        // uses unguarded, drawing the highlight and the cursor tag above the code
        // (#4796).
        let windowFocusLine = min(max(0, clampedFocusLine - startLine), max(0, endLine - startLine))
        return PreparedPlaybackWindow(
            contents: windowContents,
            focusLine: windowFocusLine,
            cursorOffset: adjustedCursor
        )
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
            resolvedParticipantNames = Self.participantNameMap(
                authors: rebuilt.participantAuthors, names: participantNames
            )
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
