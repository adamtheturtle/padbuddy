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
    let dark: Bool

    /// Idle stretches longer than this play back compressed, so a session with
    /// a ten-minute silence doesn't stall the replay.
    static let maxPlaybackGap = 3.0
    /// A floor between steps so bursts of same-millisecond edits stay visible
    /// as motion instead of collapsing into one jump.
    static let minPlaybackStep = 0.02

    static let authorPalette: [Color] = [
        .blue, .green, .orange, .purple, .pink, .teal, .indigo, .brown
    ]

    @State private var timeline: PadPlaybackTimeline
    /// The playhead: an index into `timeline.items`. Starts at the latest edit,
    /// matching what the card showed before playback existed.
    @State private var position: Int
    /// A file the user picked to view instead of the one being edited at the
    /// playhead. Cleared whenever the playhead moves, so playing and scrubbing
    /// always follow the action.
    @State private var manualFileID: String?
    @State private var isPlaying = false
    @State private var playbackSpeed = 1.0
    @State private var playbackTask: Task<Void, Never>?

    init(histories: [PadFileHistory], events: [PadEvent], dark: Bool) {
        self.histories = histories
        self.events = events
        self.dark = dark
        let timeline = PadPlaybackTimeline(histories: histories)
        _timeline = State(initialValue: timeline)
        _position = State(initialValue: max(0, timeline.items.count - 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            transportControls
            if timeline.items.count > 1 {
                PadPlaybackScrubber(
                    timeline: timeline,
                    position: position,
                    runMarkers: runMarkers,
                    color: color(forAuthor:),
                    onScrub: { setPosition($0) }
                )
                if timeline.participantAuthors.count > 1 {
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
        .onChange(of: position) { manualFileID = nil }
        .onChange(of: histories) { rebuildTimeline() }
        .onDisappear { stopPlayback() }
    }
}

extension HistoryPlaybackView {
    // MARK: Derived state

    private var displayedFileID: String? {
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
    /// moments a candidate executed their solution.
    private var runMarkers: [Double] {
        events.compactMap { event in
            guard ["ran", "executed"].contains(event.kind.lowercased()),
                  let createdAt = event.createdAt else { return nil }
            return timeline.fraction(
                atMilliseconds: Int64(createdAt.timeIntervalSince1970 * 1_000)
            )
        }
    }

    // MARK: Header

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                headerContent
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 8) {
                headerContent
            }
        }
    }

    @ViewBuilder
    private var headerContent: some View {
        if histories.count > 1 {
            Picker("File", selection: fileSelection) {
                ForEach(histories) { history in
                    Text(history.title).tag(history.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 260, alignment: .leading)
            .accessibilityLabel("History file")
        } else if let displayedFile {
            Text(displayedFile.title)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
        }
        if let displayedSnapshot {
            if let author = PadPlaybackAuthors.displayName(displayedSnapshot.entry.author) {
                MetaLabel(text: author, systemImage: "person")
            }
            MetaLabel(
                text: historyDate(displayedSnapshot.entry.timestamp),
                systemImage: "clock"
            )
        }
    }

    /// Picking a file views it as of the current playhead without moving the
    /// playhead; the next scrub or play step goes back to following the edits.
    private var fileSelection: Binding<String> {
        Binding {
            displayedFileID ?? histories.first?.id ?? ""
        } set: { newValue in
            manualFileID = newValue
        }
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
        Button { setPosition(0) } label: {
            Image(systemName: "backward.end")
        }
        .help("Show first edit")
        .accessibilityLabel("Show first edit")
        .disabled(position == 0)

        Button { setPosition(position - 1) } label: {
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

        Button { setPosition(position + 1) } label: {
            Image(systemName: "chevron.right")
        }
        .help("Show next edit")
        .accessibilityLabel("Show next edit")
        .disabled(position >= timeline.items.count - 1)

        Button { setPosition(timeline.items.count - 1) } label: {
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

    /// One compact lane per participant showing when they edited, like the web
    /// playback's attendee activity timeline. Clicking a lane jumps to that
    /// person's nearest edit. Template and upload seeds get no lane.
    private var authorLanes: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(timeline.participantAuthors, id: \.self) { author in
                PadPlaybackAuthorLane(
                    timeline: timeline,
                    author: author,
                    displayName: laneName(for: author),
                    color: color(forAuthor: author),
                    onJump: { fraction in
                        if let index = timeline.index(ofAuthor: author, nearestToFraction: fraction) {
                            setPosition(index)
                        }
                    }
                )
            }
        }
    }

    private func laneName(for author: String) -> String {
        if let name = PadPlaybackAuthors.displayName(author) { return name }
        let ordinal = (timeline.participantAuthors.firstIndex(of: author) ?? 0) + 1
        return String(localized: "Participant \(ordinal)")
    }

    /// Participants get palette colors; template and upload seeds draw gray so
    /// their ticks read as background scaffolding, not activity.
    private func color(forAuthor author: String) -> Color {
        guard let index = timeline.participantAuthors.firstIndex(of: author) else { return .gray }
        return Self.authorPalette[index % Self.authorPalette.count]
    }

    // MARK: Code

    @ViewBuilder
    private var codeBody: some View {
        if let displayedFile {
            if let displayedSnapshot {
                HighlightedCode(
                    contents: displayedSnapshot.contents,
                    language: displayedFile.language,
                    dark: dark,
                    focusLine: displayedSnapshot.changeLine,
                    // Float the editing participant's name at the cursor, like the
                    // web playback's cursor label (#985). Template/upload seeds
                    // aren't participants, so they get no tag.
                    cursorLabel: cursorLabel(for: displayedSnapshot),
                    cursorColor: color(forAuthor: displayedSnapshot.entry.author)
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
        guard timeline.participantAuthors.contains(author) else { return nil }

        return laneName(for: author)
    }

    // MARK: Playback engine

    private func setPosition(_ index: Int) {
        position = min(max(0, index), max(0, timeline.items.count - 1))
    }

    private func togglePlayback() {
        if isPlaying {
            stopPlayback()
        } else {
            startPlayback()
        }
    }

    /// Replays edits at the pace they actually happened, divided by the chosen
    /// speed, reading `position` fresh each step so scrubbing mid-play just
    /// moves the replay rather than fighting it.
    private func startPlayback() {
        stopPlayback()
        guard timeline.items.count > 1 else { return }
        if position >= timeline.items.count - 1 {
            setPosition(0)
        }
        isPlaying = true
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
            isPlaying = false
        }
    }

    private func stopPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
        isPlaying = false
    }

    private func rebuildTimeline() {
        // A background refresh replacing the histories keeps the playhead where
        // it was, except "showing the latest edit" tracks the new latest.
        let wasAtEnd = position >= timeline.items.count - 1
        timeline = PadPlaybackTimeline(histories: histories)
        let last = max(0, timeline.items.count - 1)
        position = wasAtEnd ? last : min(position, last)
    }

    // MARK: Formatting

    private func timeText(_ seconds: Double) -> String {
        let pattern: Duration.TimeFormatStyle.Pattern =
            timeline.durationSeconds >= 3_600 ? .hourMinuteSecond : .minuteSecond
        return Duration.seconds(seconds).formatted(.time(pattern: pattern))
    }

    private func historyDate(_ milliseconds: Int64) -> String {
        Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
            .formatted(date: .long, time: .shortened)
    }
}

#Preview {
    func entry(_ id: String, _ author: String, _ text: String, at time: Int64) -> PadHistoryEntry {
        PadHistoryEntry(id: id, author: author, operations: [.insert(text)], timestamp: time)
    }

    return HistoryPlaybackView(
        histories: [
            PadFileHistory(id: "main", title: "main.py", language: "python", history: PadHistory(entries: [
                entry("a", "CoderPad", "# Template\n", at: 500),
                entry("b", "Polly Sherman", "def two_sum(nums, target):\n", at: 1_000),
                entry("c", "Polly Sherman", "    seen = {}\n", at: 90_000),
                entry("d", "Garrett Wang", "    for i, n in enumerate(nums):\n", at: 200_000)
            ])),
            PadFileHistory(id: "util", title: "util.py", language: "python", history: PadHistory(entries: [
                entry("e", "Garrett Wang", "import math\n", at: 140_000)
            ]))
        ],
        events: [],
        dark: false
    )
    .padding()
    .frame(width: 480)
}
