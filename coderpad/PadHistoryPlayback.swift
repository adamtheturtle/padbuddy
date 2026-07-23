//
//  PadHistoryPlayback.swift
//  coderpad
//
//  Session playback for the History card: a unified, cross-file timeline of
//  every edit in the pad, with a play button that replays the session at its
//  real pace, a scrubber whose indicators show who edited when, and per-person
//  activity lanes. Scrubbing follows the file being edited, like the web
//  playback at app.coderpad.io/<pad>/playback.
//
//  The timeline model lives in PadPlaybackTimeline.swift and the drawn track
//  components in PadHistoryPlayback+Track.swift.
//

import SwiftUI

/// The History card's content: transport controls, the indicator timeline, the
/// per-person activity lanes, and the code as of the playhead.
struct HistoryPlaybackView: View {
    let histories: [PadFileHistory]
    let events: [PadEvent]
    let participantNames: [String]
    let dark: Bool

    /// Idle stretches longer than this play back compressed, so a session with
    /// a ten-minute silence doesn't stall the replay.
    nonisolated static let maxPlaybackGap = 3.0
    /// A floor between steps so bursts of same-millisecond edits stay visible
    /// as motion instead of collapsing into one jump.
    nonisolated static let minPlaybackStep = 1.0 / 15.0
    /// While playback is running, transport steps jump a small cluster of edits so
    /// back/forward behaves like a useful nudge rather than fighting the play loop.
    nonisolated static let playingStepJump = 5

    static let authorPalette: [Color] = [
        .blue, .green, .orange, .purple, .pink, .teal, .indigo, .brown
    ]

    private struct DisplayedCode {
        let contents: String
        let focusLine: Int?
        let cursorOffset: Int?
    }

    @State var timeline: PadPlaybackTimeline
    /// The playhead: an index into `timeline.items`. Starts at the latest edit,
    /// matching what the card showed before playback existed.
    @State var position: Int
    /// A file the user picked to view instead of the one being edited at the
    /// playhead. Cleared when the user scrubs or steps (following the action),
    /// but kept while the play loop advances, so watching one file during a
    /// replay isn't overridden on every tick (#1877).
    @State var manualFileID: String?
    @State var isPlaying = false
    @State var groupedEditCount = 0
    @State var showCurrentComparison = false
    @State var playbackTask: Task<Void, Never>?
    /// Identifies the newest timeline rebuild, so a slower off-main rebuild for
    /// an older histories value can't overwrite a newer one (#1870).
    @State var rebuildGeneration = 0
    /// Identifies the current playback session, so a cancelled older task can't
    /// switch off a newer session's `isPlaying` indicator on its way out (#1168).
    @State var playbackGeneration = 0
    /// Invalidates a frame the play loop prepared before the user manually moved
    /// the playhead. Without this, a skip can briefly publish the old destination.
    @State var playbackSeekGeneration = 0
    /// The scrubber's code-run markers, held rather than derived in `body`: they
    /// change only with the events or the timeline, while `body` re-runs on every
    /// playback tick (#2090).
    @State var runMarkers: [Double]
    /// History author ID to pad participant display name, reconciled once per
    /// timeline build rather than rebuilt for every lane on every playback frame.
    @State var resolvedParticipantNames: [String: String]
    /// The current playback snapshot is highlighted before its position is
    /// published, preventing the plain-to-colored flash between rapid edits.
    @State var preparedHighlightedText: AttributedString?
    @State var preparedHighlightedContents: String?
    @State var preparedHighlightedDark: Bool?
    @State var preparedPlaybackFileID: String?
    @State var preparedPlaybackSnapshotIndex: Int?
    @State var preparedPlaybackContents: String?
    @State var preparedPlaybackFocusLine: Int?
    @State var preparedPlaybackCursorOffset: Int?

    init(histories: [PadFileHistory], events: [PadEvent], dark: Bool, participantNames: [String] = []) {
        self.histories = histories
        self.events = events
        self.participantNames = participantNames
        self.dark = dark
        let timeline = PadPlaybackTimeline(histories: histories)
        _timeline = State(initialValue: timeline)
        _position = State(initialValue: PlaybackPositionStore.position(in: timeline, histories: histories))
        _runMarkers = State(initialValue: Self.runMarkers(events: events, timeline: timeline))
        _resolvedParticipantNames = State(initialValue: Self.participantNameMap(
            authors: timeline.participantAuthors, names: participantNames
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if histories.count > 1 { filePicker }
            playbackBar
            codeBody
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: historiesSignature) {
            // The rebuild itself stops any running replay first (#1167, #1868).
            rebuildTimeline()
        }
        .onChange(of: eventsSignature) {
            runMarkers = Self.runMarkers(events: events, timeline: timeline)
        }
        .persistPlaybackPosition($position, timeline: timeline, histories: histories, isPlaying: isPlaying)
        .sheet(isPresented: $showCurrentComparison) { comparisonViewer }
        .onDisappear { stopPlayback() }
    }
}

extension HistoryPlaybackView {
    // MARK: Derived state

    var displayedFileID: String? {
        manualFileID
            ?? (timeline.items.indices.contains(position) ? timeline.items[position].fileID : nil)
            ?? histories.first?.id
    }

    var displayedFile: PadFileHistory? {
        histories.first { $0.id == displayedFileID } ?? histories.first
    }

    var displayedSnapshot: PadHistorySnapshot? {
        guard let displayedFile else { return nil }
        guard let index = timeline.snapshotIndex(of: displayedFile.id, at: position),
              displayedFile.snapshots.indices.contains(index) else { return nil }

        return displayedFile.snapshots[index]
    }

    /// Where code runs happened, as track positions, so the timeline marks the
    /// moments a candidate executed their solution. Deduplicated per rendered
    /// half-pixel and bounded, so a pathological event feed can't stroke
    /// thousands of overlapping diamonds every frame (#1882).
    ///
    /// Computed on demand rather than in `body`: the result depends only on the
    /// events and the timeline, but `position` changes on every play-loop tick,
    /// so a computed property read from `body` rescanned the whole event feed
    /// several times a second (#2090). Callers cache it in `runMarkers`.
    nonisolated static func runMarkers(events: [PadEvent], timeline: PadPlaybackTimeline) -> [Double] {
        var seenBuckets = Set<Int>()
        var markers: [Double] = []
        for event in events {
            guard ["ran", "executed"].contains(event.kind.lowercased()),
                  let createdAt = event.createdAt else { continue }

            // Event dates are remote data: a date outside the timeline's sane
            // range would trap the Double→Int64 conversion (#1171). Out-of-range
            // events simply draw no marker.
            let milliseconds = createdAt.timeIntervalSince1970 * 1000
            guard milliseconds >= Double(PadPlaybackTimeline.timestampRange.lowerBound),
                  milliseconds <= Double(PadPlaybackTimeline.timestampRange.upperBound),
                  let fraction = timeline.fraction(atMilliseconds: Int64(milliseconds)) else { continue }

            if seenBuckets.insert(Int(fraction * 2000)).inserted {
                markers.append(fraction)
                if markers.count >= 500 { break }
            }
        }
        return markers
    }

    // MARK: Transport

    @ViewBuilder
    private var playbackBar: some View {
        if timeline.items.count > 1 {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    transportCluster
                    timelineStrip
                        .frame(minWidth: 160)
                    playbackStatus
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        transportCluster
                        playbackStatus
                    }
                    timelineStrip
                }
            }
            .historyPlaybackBarChrome()
        } else {
            Text("Only one edit")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .historyPlaybackBarChrome()
                .accessibilityLabel("History contains only one edit")
        }
    }

    private var transportCluster: some View {
        HStack(spacing: 3) {
            stepButtons
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(3)
        .background(.background.opacity(0.65), in: Capsule())
        .overlay {
            Capsule()
                .stroke(.secondary.opacity(0.12), lineWidth: 0.5)
        }
    }

    private var timelineStrip: some View {
        PadPlaybackScrubber(
            timeline: timeline,
            position: position,
            runMarkers: runMarkers,
            color: color(forAuthor:),
            showsRunMarkerHelp: !isPlaying,
            onScrub: { userSetPosition($0) }
        )
    }

    private var playbackStatus: some View {
        HStack(spacing: 6) {
            Text("\(position + 1)")
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            Text("/ \(timeline.items.count)")
            if timeline.durationSeconds > 0 {
                Text("•")
                    .foregroundStyle(.tertiary)
                Text("\(timeText(timeline.elapsedSeconds(at: position)))")
                    .monospacedDigit()
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("History revision")
        .accessibilityValue("\(position + 1) of \(timeline.items.count)")
    }

    @ViewBuilder
    private var stepButtons: some View {
        compareButton
        Button { userSetPosition(0) } label: {
            Image(systemName: "backward.end")
                .frame(width: 24, height: 24)
        }
        .help("Show first edit")
        .accessibilityLabel("Show first edit")
        .disabled(position == 0)

        Button { userStepPosition(by: -1) } label: {
            Image(systemName: "chevron.left")
                .frame(width: 24, height: 24)
        }
        .help("Show previous edit")
        .accessibilityLabel("Show previous edit")
        .keyboardShortcut(.leftArrow, modifiers: [])
        .disabled(position == 0)

        Button { togglePlayback() } label: {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.caption.weight(.bold))
                .frame(width: 30, height: 30)
                .foregroundStyle(.white)
                .background(.tint, in: Circle())
                .shadow(color: .accentColor.opacity(isPlaying ? 0.24 : 0.14), radius: 4, y: 1)
        }
        .help(isPlaying ? "Pause playback" : "Play the session")
        .accessibilityLabel(isPlaying ? "Pause playback" : "Play the session")
        .disabled(timeline.items.count < 2)

        Button { userStepPosition(by: 1) } label: {
            Image(systemName: "chevron.right")
                .frame(width: 24, height: 24)
        }
        .help("Show next edit")
        .accessibilityLabel("Show next edit")
        .keyboardShortcut(.rightArrow, modifiers: [])
        .disabled(position >= timeline.items.count - 1)

        Button { userSetPosition(timeline.items.count - 1) } label: {
            Image(systemName: "forward.end")
                .frame(width: 24, height: 24)
        }
        .help("Show latest edit")
        .accessibilityLabel("Show latest edit")
        .disabled(position >= timeline.items.count - 1)
    }

    /// Participant colors stay distinct; template and upload seeds remain gray.
    private func color(forAuthor author: String) -> Color {
        guard let index = timeline.participantIndex[author] else { return .gray }

        if index < Self.authorPalette.count { return Self.authorPalette[index] }

        let extraCount = max(timeline.participantAuthors.count - Self.authorPalette.count, 1)
        let extraIndex = index - Self.authorPalette.count
        return Color(hue: Double(extraIndex) / Double(extraCount) * 0.9,
                     saturation: 0.65, brightness: 0.75)
    }

    // MARK: Code

    @ViewBuilder
    private var codeBody: some View {
        if let displayedFile {
            if let displayedSnapshot {
                let displayedCode = displayedCode(for: displayedFile, snapshot: displayedSnapshot)
                HighlightedCode(
                    contents: displayedCode.contents,
                    language: displayedFile.language,
                    dark: dark,
                    focusLine: displayedCode.focusLine,
                    cursorOffset: displayedCode.cursorOffset,
                    // Float the editing participant's name at the cursor, like the
                    // web playback's cursor label (#985). Template/upload seeds
                    // aren't participants, so they get no tag.
                    cursorLabel: cursorLabel(for: displayedSnapshot),
                    scrollIdentity: "\(displayedFile.id)#\(displayedSnapshot.id)",
                    cursorColor: color(forAuthor: displayedSnapshot.entry.author),
                    allowsHighlighting: !isPlaying,
                    contentIdentity: isPlaying ? "\(displayedFile.id)#\(displayedSnapshot.id)" : nil,
                    preparedHighlightedText: preparedHighlightedText,
                    preparedHighlightedContents: preparedHighlightedContents,
                    preparedHighlightedDark: preparedHighlightedDark
                )
                .equatable()
                // The same backing the code card gives its code pane, so replayed
                // source reads as code rather than floating on the card (#984).
                .background(Color.subtleStroke.opacity(0.5),
                            in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            } else {
                Text("\(displayedFile.title) has no edits yet at this point in the session.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func displayedCode(
        for file: PadFileHistory,
        snapshot: PadHistorySnapshot
    ) -> DisplayedCode {
        if isPlaying,
           preparedPlaybackFileID == file.id,
           preparedPlaybackSnapshotIndex == snapshot.index {
            return DisplayedCode(
                contents: preparedPlaybackContents ?? "",
                focusLine: preparedPlaybackFocusLine,
                cursorOffset: preparedPlaybackCursorOffset
            )
        }

        guard let contents = file.contents(at: snapshot.index) else {
            return DisplayedCode(contents: "", focusLine: snapshot.cursorLine, cursorOffset: snapshot.cursorOffset)
        }

        let window = Self.playbackWindow(
            contents: contents,
            focusLine: snapshot.cursorLine,
            cursorOffset: snapshot.cursorOffset
        )
        return DisplayedCode(contents: window.contents, focusLine: window.focusLine, cursorOffset: window.cursorOffset)
    }

    /// Float a name only when history provides one we can identify. Opaque
    /// connection IDs remain distinguishable by their stable colors without
    /// inventing a “Participant N” identity (#2922).
    private func cursorLabel(for snapshot: PadHistorySnapshot) -> String? {
        let author = snapshot.entry.author
        guard timeline.isParticipant(author) else { return nil }

        return resolvedParticipantNames[author] ?? PadPlaybackAuthors.displayName(author)
    }

    // MARK: Formatting
}
