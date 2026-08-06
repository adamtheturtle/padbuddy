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
    let showsRunMarkerHelp: Bool
    let onScrub: (Int) -> Void

    private let playbackColor = HistoryPlaybackView.playbackControlColor

    @State private var dragPosition: Int?

    private var visualPosition: Int {
        dragPosition ?? position
    }

    var body: some View {
        GeometryReader { geometry in
            layers
                .overlay {
                    if showsRunMarkerHelp {
                        runMarkerHelp(width: geometry.size.width)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            dragPosition = timeline.index(
                                atFraction: value.location.x / max(geometry.size.width, 1)
                            )
                        }
                        .onEnded { value in
                            let index = timeline.index(
                                atFraction: value.location.x / max(geometry.size.width, 1)
                            )
                            dragPosition = nil
                            onScrub(index)
                        }
                )
        }
        .frame(height: 38)
        .padding(.horizontal, 10)
        .background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.secondary.opacity(0.12), lineWidth: 0.5)
        }
        .accessibilityElement()
        .accessibilityLabel("Playback timeline")
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onScrub(position + 1)
            case .decrement: onScrub(position - 1)
            @unknown default: break
            }
        }
    }

    private var accessibilityValue: String {
        let edit = String(localized: "Edit \(visualPosition + 1) of \(timeline.items.count)")
        let count = timeline.compressedGaps.count
        guard count > 0 else { return edit }

        return "\(edit), \(String(localized: "\(count) long idle gaps compressed"))"
    }

    /// Canvas marks cannot expose their own hover help, so give every run marker
    /// a small transparent hit target with the meaning users need (#2916).
    private func runMarkerHelp(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            ForEach(Array(runMarkers.enumerated()), id: \.offset) { _, marker in
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: 14, height: 14)
                    .offset(x: marker * width - 7, y: -5)
                    .help("Code execution")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
        progress.addLine(to: CGPoint(x: timeline.fraction(at: visualPosition) * size.width, y: trackY))
        context.stroke(
            progress, with: .color(.secondary.opacity(0.16)),
            style: StrokeStyle(lineWidth: 9, lineCap: .round)
        )
        context.stroke(
            progress, with: .color(playbackColor.opacity(0.52)),
            style: StrokeStyle(lineWidth: 4, lineCap: .round)
        )
    }

    private func drawPlayhead(_ context: inout GraphicsContext, size: CGSize, trackY: CGFloat) {
        let playheadX = timeline.fraction(at: visualPosition) * size.width
        var playhead = Path()
        playhead.move(to: CGPoint(x: playheadX, y: trackY - 11))
        playhead.addLine(to: CGPoint(x: playheadX, y: trackY + 11))
        context.stroke(
            playhead, with: .color(playbackColor.opacity(0.72)),
            style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
        )
        let halo = Path(ellipseIn: CGRect(x: playheadX - 8, y: trackY - 8, width: 16, height: 16))
        context.fill(halo, with: .color(.white.opacity(0.82)))
        context.stroke(halo, with: .color(playbackColor.opacity(0.18)), lineWidth: 1)
        let knob = Path(ellipseIn: CGRect(x: playheadX - 5, y: trackY - 5, width: 10, height: 10))
        context.fill(knob, with: .color(playbackColor.opacity(0.8)))
        context.stroke(knob, with: .color(.white.opacity(0.9)), lineWidth: 1.5)
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
    static let trackYFraction = 0.58

    /// The color mapping is derived from the timeline's participant order, so
    /// comparing the data covers the closure too.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.timeline.trackRenderKey == rhs.timeline.trackRenderKey
            && lhs.runMarkers == rhs.runMarkers
    }

    var body: some View {
        Canvas { context, size in
            let trackY = size.height * Self.trackYFraction
            drawTrack(&context, size: size, trackY: trackY)
            drawCompressedGaps(&context, size: size, trackY: trackY)
            drawTicks(&context, size: size, trackY: trackY)
            drawRunMarkers(&context, size: size, trackY: trackY)
        }
    }

    private func drawCompressedGaps(_ context: inout GraphicsContext, size: CGSize, trackY: CGFloat) {
        for gap in timeline.compressedGaps {
            let positionX = gap.fraction * size.width
            for offset in [-3.0, 3.0] {
                var notch = Path()
                notch.move(to: CGPoint(x: positionX + offset - 2, y: trackY + 5))
                notch.addLine(to: CGPoint(x: positionX + offset + 2, y: trackY - 5))
                context.stroke(notch, with: .color(.secondary), lineWidth: 1.5)
            }
        }
    }

    private func drawTrack(_ context: inout GraphicsContext, size: CGSize, trackY: CGFloat) {
        var track = Path()
        track.move(to: CGPoint(x: 0, y: trackY))
        track.addLine(to: CGPoint(x: size.width, y: trackY))
        context.stroke(
            track, with: .color(.secondary.opacity(0.18)),
            style: StrokeStyle(lineWidth: 9, lineCap: .round)
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
            tick.move(to: CGPoint(x: tickX, y: trackY - 6))
            tick.addLine(to: CGPoint(x: tickX, y: trackY + 6))
            context.stroke(
                tick, with: .color(color(item.author).opacity(0.9)),
                style: StrokeStyle(lineWidth: 2, lineCap: .round)
            )
        }
    }

    /// Code runs sit above the track as small diamonds, distinct from the edit
    /// ticks below.
    private func drawRunMarkers(_ context: inout GraphicsContext, size: CGSize, trackY: CGFloat) {
        for marker in runMarkers {
            let markerX = marker * size.width
            let markerY = trackY - 12
            var diamond = Path()
            diamond.move(to: CGPoint(x: markerX, y: markerY - 3))
            diamond.addLine(to: CGPoint(x: markerX + 3, y: markerY))
            diamond.addLine(to: CGPoint(x: markerX, y: markerY + 3))
            diamond.addLine(to: CGPoint(x: markerX - 3, y: markerY))
            diamond.closeSubpath()
            context.fill(diamond, with: .color(.orange))
            context.stroke(diamond, with: .color(.white.opacity(0.8)), lineWidth: 0.75)
        }
    }
}
