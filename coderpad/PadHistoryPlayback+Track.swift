//
//  PadHistoryPlayback+Track.swift
//  coderpad
//
//  The drawn parts of session playback: the scrubbable timeline track with a
//  tick per edit, run markers, and the playhead; and the per-participant
//  activity lanes beneath it.
//

import SwiftUI

/// The timeline track: a time-proportional scrubber with a tick per edit in
/// its author's color, run markers above the track, and a draggable playhead.
struct PadPlaybackScrubber: View {
    let timeline: PadPlaybackTimeline
    let position: Int
    let runMarkers: [Double]
    let color: (String) -> Color
    let onScrub: (Int) -> Void

    var body: some View {
        GeometryReader { geometry in
            layers
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            onScrub(timeline.index(
                                atFraction: value.location.x / max(geometry.size.width, 1)
                            ))
                        }
                )
        }
        .frame(height: 26)
        .accessibilityElement()
        .accessibilityLabel("Playback timeline")
        .accessibilityValue("Edit \(position + 1) of \(timeline.items.count)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onScrub(position + 1)
            case .decrement: onScrub(position - 1)
            @unknown default: break
            }
        }
    }

    /// The ticks and run markers don't depend on the playhead, so they draw in
    /// their own layer that scrubbing never invalidates: a drag update redraws
    /// only the lightweight progress/playhead layer, not a tick per edit (#1873).
    private var layers: some View {
        ZStack {
            PadPlaybackTrackBase(timeline: timeline, runMarkers: runMarkers, color: color)
                .equatable()
            playheadLayer
        }
    }

    private var playheadLayer: some View {
        Canvas { context, size in
            let trackY = size.height * PadPlaybackTrackBase.trackYFraction
            drawProgress(&context, size: size, trackY: trackY)
            drawPlayhead(&context, size: size, trackY: trackY)
        }
    }

    private func drawProgress(_ context: inout GraphicsContext, size: CGSize, trackY: CGFloat) {
        var progress = Path()
        progress.move(to: CGPoint(x: 0, y: trackY))
        progress.addLine(to: CGPoint(x: timeline.fraction(at: position) * size.width, y: trackY))
        context.stroke(
            progress, with: .color(.accentColor.opacity(0.45)),
            style: StrokeStyle(lineWidth: 3, lineCap: .round)
        )
    }

    private func drawPlayhead(_ context: inout GraphicsContext, size: CGSize, trackY: CGFloat) {
        let playheadX = timeline.fraction(at: position) * size.width
        var playhead = Path()
        playhead.move(to: CGPoint(x: playheadX, y: trackY - 8))
        playhead.addLine(to: CGPoint(x: playheadX, y: trackY + 8))
        context.stroke(
            playhead, with: .color(.accentColor),
            style: StrokeStyle(lineWidth: 2, lineCap: .round)
        )
        let knob = Path(ellipseIn: CGRect(x: playheadX - 3.5, y: trackY - 3.5, width: 7, height: 7))
        context.fill(knob, with: .color(.accentColor))
    }
}

/// The scrubber's playhead-independent layer: the base track line, one tick per
/// edit, and the run markers. Equatable on its data so drag updates (which only
/// move the playhead) never re-render it (#1873).
struct PadPlaybackTrackBase: View, Equatable {
    let timeline: PadPlaybackTimeline
    let runMarkers: [Double]
    let color: (String) -> Color

    /// Where the track line sits, as a fraction of the canvas height; shared
    /// with the playhead layer so the two layers line up.
    static let trackYFraction = 0.62

    // The color mapping is derived from the timeline's participant order, so
    // comparing the data covers the closure too.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.timeline == rhs.timeline && lhs.runMarkers == rhs.runMarkers
    }

    var body: some View {
        Canvas { context, size in
            let trackY = size.height * Self.trackYFraction
            drawTrack(&context, size: size, trackY: trackY)
            drawTicks(&context, size: size, trackY: trackY)
            drawRunMarkers(&context, size: size, trackY: trackY)
        }
    }

    private func drawTrack(_ context: inout GraphicsContext, size: CGSize, trackY: CGFloat) {
        var track = Path()
        track.move(to: CGPoint(x: 0, y: trackY))
        track.addLine(to: CGPoint(x: size.width, y: trackY))
        context.stroke(
            track, with: .color(.secondary.opacity(0.25)),
            style: StrokeStyle(lineWidth: 3, lineCap: .round)
        )
    }

    /// One tick per edit, deduplicated per pixel and author so a long session
    /// doesn't stroke thousands of overlapping lines. Dedup keys are packed
    /// integers, not per-item strings, to keep the draw allocation-free (#1873).
    private func drawTicks(_ context: inout GraphicsContext, size: CGSize, trackY: CGFloat) {
        var authorIndexes: [String: Int] = [:]
        for (index, author) in timeline.authors.enumerated() {
            authorIndexes[author] = index
        }
        let authorCount = max(timeline.authors.count, 1)
        var drawn = Set<Int>()
        for index in timeline.items.indices {
            let item = timeline.items[index]
            let tickX = (timeline.fraction(at: index) * size.width).rounded()
            let key = Int(tickX) * authorCount + (authorIndexes[item.author] ?? 0)
            guard drawn.insert(key).inserted else { continue }
            var tick = Path()
            tick.move(to: CGPoint(x: tickX, y: trackY - 5))
            tick.addLine(to: CGPoint(x: tickX, y: trackY + 5))
            context.stroke(
                tick, with: .color(color(item.author).opacity(0.8)),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
            )
        }
    }

    /// Code runs sit above the track as small diamonds, distinct from the edit
    /// ticks below.
    private func drawRunMarkers(_ context: inout GraphicsContext, size: CGSize, trackY: CGFloat) {
        for marker in runMarkers {
            let markerX = marker * size.width
            let markerY = trackY - 9
            var diamond = Path()
            diamond.move(to: CGPoint(x: markerX, y: markerY - 3))
            diamond.addLine(to: CGPoint(x: markerX + 3, y: markerY))
            diamond.addLine(to: CGPoint(x: markerX, y: markerY + 3))
            diamond.addLine(to: CGPoint(x: markerX - 3, y: markerY))
            diamond.closeSubpath()
            context.fill(diamond, with: .color(.orange))
        }
    }
}

/// One participant's row under the scrubber: a color key, their name, and a
/// mini-track of their edits. Clicking the track jumps to their nearest edit.
struct PadPlaybackAuthorLane: View {
    let timeline: PadPlaybackTimeline
    let author: String
    let displayName: String
    let color: Color
    let onJump: (Double) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 110, alignment: .leading)
            lane
        }
        .accessibilityElement()
        .accessibilityLabel("\(displayName) activity")
    }

    private var lane: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let midY = size.height / 2
                var drawn = Set<Int>()
                for index in timeline.items.indices
                    where timeline.items[index].author == author {
                    let tickX = (timeline.fraction(at: index) * size.width).rounded()
                    guard drawn.insert(Int(tickX)).inserted else { continue }
                    var tick = Path()
                    tick.move(to: CGPoint(x: tickX, y: midY - 3))
                    tick.addLine(to: CGPoint(x: tickX, y: midY + 3))
                    context.stroke(
                        tick, with: .color(color.opacity(0.8)),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                    )
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        onJump(value.location.x / max(geometry.size.width, 1))
                    }
            )
        }
        .frame(height: 10)
    }
}
