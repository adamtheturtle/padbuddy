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

    static let authorPalette: [Color] = [
        .blue, .green, .orange, .purple, .pink, .teal, .indigo, .brown
    ]

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
    @State var playbackSpeed = 1.0
    @State var playbackTask: Task<Void, Never>?
    /// Identifies the newest timeline rebuild, so a slower off-main rebuild for
    /// an older histories value can't overwrite a newer one (#1870).
    @State var rebuildGeneration = 0
    /// Identifies the current playback session, so a cancelled older task can't
    /// switch off a newer session's `isPlaying` indicator on its way out (#1168).
    @State var playbackGeneration = 0
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

    init(histories: [PadFileHistory], events: [PadEvent], dark: Bool, participantNames: [String] = []) {
        self.histories = histories
        self.events = events
        self.participantNames = participantNames
        self.dark = dark
        let timeline = PadPlaybackTimeline(histories: histories)
        _timeline = State(initialValue: timeline)
        _position = State(initialValue: max(0, timeline.items.count - 1))
        _runMarkers = State(initialValue: Self.runMarkers(events: events, timeline: timeline))
        _resolvedParticipantNames = State(initialValue: Self.participantNameMap(
            authors: timeline.participantAuthors, names: participantNames
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if histories.count > 1 { filePicker }
            transportControls
            if timeline.items.count > 1 {
                trackLabel("Session edits", detail: "Colored ticks are edits; orange diamonds are code runs.")
                PadPlaybackScrubber(
                    timeline: timeline,
                    position: position,
                    runMarkers: runMarkers,
                    color: color(forAuthor:),
                    onScrub: { userSetPosition($0) }
                )
                .padding(.leading, PadPlaybackAuthorLane.trackLeadingInset)
                if timeline.participantAuthors.count > 1 {
                    trackLabel("Participant activity")
                    authorLanes
                }
            } else {
                Text("Only one edit")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
        .onChange(of: playbackSpeed) {
            // A sleeping play step keeps the delay it computed at the old
            // speed; restarting the loop retimes the pending gap so a speed
            // change takes effect immediately (#1878).
            if isPlaying { startPlayback() }
        }
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

    private var displayedFile: PadFileHistory? {
        histories.first { $0.id == displayedFileID } ?? histories.first
    }

    private var displayedSnapshot: PadHistorySnapshot? {
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

    private var transportControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { transportContent }
            VStack(alignment: .leading, spacing: 8) { transportContent }
        }
    }

    @ViewBuilder
    private var transportContent: some View {
        HStack(spacing: 4) {
            stepButtons
        }
        .buttonStyle(.borderless)
        .controlSize(.small)

        speedPicker

        if timeline.durationSeconds > 0 {
            Text("\(timeText(timeline.elapsedSeconds(at: position))) / \(timeText(timeline.durationSeconds))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var stepButtons: some View {
        Button { userSetPosition(0) } label: {
            Image(systemName: "backward.end")
        }
        .help("Show first edit")
        .accessibilityLabel("Show first edit")
        .disabled(position == 0)

        Button { userSetPosition(position - 1) } label: {
            Image(systemName: "chevron.left")
        }
        .help("Show previous edit")
        .accessibilityLabel("Show previous edit")
        .disabled(position == 0)

        Button { togglePlayback() } label: {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
        }
        .help(isPlaying ? "Pause playback" : "Play the session")
        .accessibilityLabel(isPlaying ? "Pause playback" : "Play the session")
        .disabled(timeline.items.count < 2)

        Button { userSetPosition(position + 1) } label: {
            Image(systemName: "chevron.right")
        }
        .help("Show next edit")
        .accessibilityLabel("Show next edit")
        .disabled(position >= timeline.items.count - 1)

        Button { userSetPosition(timeline.items.count - 1) } label: {
            Image(systemName: "forward.end")
        }
        .help("Show latest edit")
        .accessibilityLabel("Show latest edit")
        .disabled(position >= timeline.items.count - 1)
    }

    private var speedPicker: some View {
        Picker("Speed", selection: $playbackSpeed) {
            ForEach([1.0, 2.0, 4.0, 8.0], id: \.self) { speed in
                Text("\(Int(speed))×").tag(speed)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .fixedSize()
        .help("Playback speed")
        .accessibilityLabel("Playback speed")
    }

    // MARK: Activity lanes

    /// How many participant lanes render before the list is summarized: a
    /// malformed or enormous session must not stack an unbounded lane per
    /// connection id (#1874).
    static let maxAuthorLanes = 12

    /// One compact lane per participant showing when they edited, like the web
    /// playback's attendee activity timeline. Clicking a lane jumps to that
    /// person's nearest edit. Template and upload seeds get no lane.
    private var authorLanes: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(timeline.participantAuthors.prefix(Self.maxAuthorLanes), id: \.self) { author in
                PadPlaybackAuthorLane(
                    timeline: timeline,
                    author: author,
                    displayName: laneName(for: author),
                    color: color(forAuthor: author),
                    onJump: { fraction in
                        if let index = timeline.index(ofAuthor: author, nearestToFraction: fraction) {
                            userSetPosition(index)
                        }
                    }
                )
            }
            if timeline.participantAuthors.count > Self.maxAuthorLanes {
                Text("and \(timeline.participantAuthors.count - Self.maxAuthorLanes) more participants")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func laneName(for author: String) -> String {
        if let name = resolvedParticipantNames[author] { return name }
        if let name = PadPlaybackAuthors.displayName(author) { return name }
        let ordinal = (timeline.participantIndex[author] ?? 0) + 1
        return String(localized: "Participant \(ordinal)")
    }

    /// Reconcile only names that the history itself identifies. The pad participant
    /// array and history connection IDs share no identifier or guaranteed ordering;
    /// assigning leftover names by position can put the wrong person's name on the
    /// active cursor (#2915). Opaque authors therefore keep a stable, honest
    /// “Participant N” label until CoderPad exposes an authoritative mapping.
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

    /// Participants get palette colors; template and upload seeds draw gray so
    /// their ticks read as background scaffolding, not activity. Past the
    /// palette, colors are generated on distinct hues rather than cycling, so
    /// two participants never share a color (#1875).
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
                HighlightedCode(
                    contents: displayedFile.contents(at: displayedSnapshot.index) ?? "",
                    language: displayedFile.language,
                    dark: dark,
                    focusLine: displayedSnapshot.cursorLine,
                    cursorOffset: displayedSnapshot.cursorOffset,
                    // Float the editing participant's name at the cursor, like the
                    // web playback's cursor label (#985). Template/upload seeds
                    // aren't participants, so they get no tag.
                    cursorLabel: cursorLabel(for: displayedSnapshot),
                    cursorColor: color(forAuthor: displayedSnapshot.entry.author),
                    allowsHighlighting: !isPlaying,
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

    /// The name to float at the playhead's cursor: the participant who authored
    /// the shown snapshot, with the same "Participant N" fallback as their lane.
    /// Nil for template/upload seeds, which aren't anyone's cursor.
    private func cursorLabel(for snapshot: PadHistorySnapshot) -> String? {
        let author = snapshot.entry.author
        guard timeline.isParticipant(author) else { return nil }

        return laneName(for: author)
    }

    // MARK: Formatting
}
