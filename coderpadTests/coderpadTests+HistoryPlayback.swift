//
//  coderpadTests+HistoryPlayback.swift
//  coderpadTests
//

@testable import CoderPad
import Foundation
import Testing

// MARK: - Playback timeline (unified cross-file history)

/// An entry that inserts one character, so snapshot construction succeeds
/// without the tests caring about the contents.
private func edit(_ id: String, by author: String, at timestamp: Int64) -> PadHistoryEntry {
    PadHistoryEntry(id: id, author: author, operations: [.insert("x")], timestamp: timestamp)
}

private func makeFile(_ id: String, title: String, entries: [PadHistoryEntry]) -> PadFileHistory {
    PadFileHistory(id: id, title: title, language: "python", history: PadHistory(entries: entries))
}

struct PadPlaybackTimelineTests {
    /// Two files whose edits interleave in time: main.py at 1_000 and 5_000,
    /// util.py at 3_000. Basil writes main.py, Sybil writes util.py.
    private var interleaved: PadPlaybackTimeline {
        PadPlaybackTimeline(histories: [
            makeFile("main", title: "main.py", entries: [
                edit("a", by: "Basil", at: 1_000), edit("b", by: "Basil", at: 5_000)
            ]),
            makeFile("util", title: "util.py", entries: [
                edit("c", by: "Sybil", at: 3_000)
            ])
        ])
    }

    @Test
    func `merges edits across files in chronological order`() {
        let timeline = interleaved

        #expect(timeline.items.map(\.fileID) == ["main", "util", "main"])
        #expect(timeline.items.map(\.timestamp) == [1_000, 3_000, 5_000])
        #expect(timeline.items.map(\.snapshotIndex) == [0, 0, 1])
    }

    @Test
    func `authors are listed in order of first edit`() {
        #expect(interleaved.authors == ["Basil", "Sybil"])
        #expect(interleaved.participantAuthors == ["Basil", "Sybil"])
    }

    /// A realistic session: CoderPad seeds the template files, a bulk upload
    /// stamps each file with a one-shot Firebase push id, and one anonymous
    /// connection does the actual typing. Only that connection is a participant.
    @Test
    func `template and upload seeds are not participants`() {
        let timeline = PadPlaybackTimeline(histories: [
            makeFile("main", title: "main.py", entries: [
                edit("a", by: "CoderPad", at: 1_000),
                edit("b", by: "4503601411610331", at: 5_000),
                edit("c", by: "4503601411610331", at: 6_000)
            ]),
            makeFile("paper", title: "main.tex", entries: [
                edit("d", by: "-OxgyokRDnSHVMqK74T0", at: 2_000)
            ]),
            makeFile("bib", title: "bib.bib", entries: [
                edit("e", by: "-OxgyoikD2X41FKTCSWo", at: 2_100)
            ])
        ])

        #expect(timeline.authors.count == 4)
        #expect(timeline.participantAuthors == ["4503601411610331"])
    }

    @Test
    func `fractions are proportional to session time`() {
        let timeline = interleaved

        #expect(timeline.durationSeconds == 4)
        #expect(timeline.fraction(at: 0) == 0)
        #expect(timeline.fraction(at: 1) == 0.5)
        #expect(timeline.fraction(at: 2) == 1)
    }

    @Test
    func `scrubbing lands on the last edit at or before the target time`() {
        let timeline = interleaved

        // 25% of a 1_000...5_000 session is 2_000ms: after the first edit,
        // before the second.
        #expect(timeline.index(atFraction: 0.25) == 0)
        #expect(timeline.index(atFraction: 0.5) == 1)
        #expect(timeline.index(atFraction: 0.99) == 1)
        #expect(timeline.index(atFraction: 1) == 2)
        // Out-of-range drags clamp instead of crashing.
        #expect(timeline.index(atFraction: -1) == 0)
        #expect(timeline.index(atFraction: 2) == 2)
    }

    @Test
    func `identical timestamps fall back to even index spacing`() {
        let timeline = PadPlaybackTimeline(histories: [
            makeFile("main", title: "main.py", entries: [
                edit("a", by: "Basil", at: 7), edit("b", by: "Basil", at: 7), edit("c", by: "Basil", at: 7)
            ])
        ])

        #expect(timeline.durationSeconds == 0)
        #expect(timeline.fraction(at: 1) == 0.5)
        #expect(timeline.index(atFraction: 0.5) == 1)
        #expect(timeline.index(atFraction: 1) == 2)
    }

    @Test
    func `file state at the playhead is its last edit at or before it`() {
        let timeline = interleaved

        // At the playhead's first edit, util.py hasn't been touched yet.
        #expect(timeline.snapshotIndex(of: "util", at: 0) == nil)
        // While Sybil edits util.py, main.py still shows its first snapshot.
        #expect(timeline.snapshotIndex(of: "main", at: 1) == 0)
        #expect(timeline.snapshotIndex(of: "util", at: 1) == 0)
        // At the end, main.py shows its second snapshot.
        #expect(timeline.snapshotIndex(of: "main", at: 2) == 1)
    }

    @Test
    func `gaps and elapsed time come from the wall clock`() {
        let timeline = interleaved

        #expect(timeline.gapSeconds(after: 0) == 2)
        #expect(timeline.gapSeconds(after: 2) == 0)
        #expect(timeline.elapsedSeconds(at: 0) == 0)
        #expect(timeline.elapsedSeconds(at: 2) == 4)
    }

    @Test
    func `jumping to an author finds their edit nearest the drop point`() {
        let timeline = interleaved

        // Dropping at the end of Sybil's lane jumps to her one edit at 3_000.
        #expect(timeline.index(ofAuthor: "Sybil", nearestToFraction: 1) == 1)
        // 0.6 of the track is equidistant from Basil's two edits; ties keep the earlier.
        #expect(timeline.index(ofAuthor: "Basil", nearestToFraction: 0.6) == 0)
        #expect(timeline.index(ofAuthor: "Basil", nearestToFraction: 1) == 2)
        #expect(timeline.index(ofAuthor: "Nobody", nearestToFraction: 0.5) == nil)
    }

    @Test
    func `event instants map onto the track and outside instants do not`() {
        let timeline = interleaved

        #expect(timeline.fraction(atMilliseconds: 3_000) == 0.5)
        #expect(timeline.fraction(atMilliseconds: 500) == nil)
        #expect(timeline.fraction(atMilliseconds: 9_000) == nil)
    }

    @Test
    func `an empty timeline is inert`() {
        let timeline = PadPlaybackTimeline(histories: [])

        #expect(timeline.items.isEmpty)
        #expect(timeline.durationSeconds == 0)
        #expect(timeline.index(atFraction: 0.5) == 0)
        #expect(timeline.snapshotIndex(of: "main", at: 0) == nil)
    }
}

struct PadPlaybackAuthorsTests {
    @Test
    func `numeric or letterless firebase ids are not display names`() {
        #expect(PadPlaybackAuthors.displayName("Polly Sherman") == "Polly Sherman")
        #expect(PadPlaybackAuthors.displayName("  Polly  ") == "Polly")
        #expect(PadPlaybackAuthors.displayName("1748291") == nil)
        #expect(PadPlaybackAuthors.displayName("!!!") == nil)
        #expect(PadPlaybackAuthors.displayName("") == nil)
        #expect(PadPlaybackAuthors.displayName(String(repeating: "a", count: 90)) == nil)
        // Upload push ids contain letters but are not names.
        #expect(PadPlaybackAuthors.displayName("-OxgyokRDnSHVMqK74T0") == nil)
    }

    @Test
    func `participants are people or editor connections, not seeds`() {
        #expect(PadPlaybackAuthors.isParticipant("Polly Sherman"))
        #expect(PadPlaybackAuthors.isParticipant("4503601411610331"))
        #expect(!PadPlaybackAuthors.isParticipant("CoderPad"))
        #expect(!PadPlaybackAuthors.isParticipant("-OxgyokRDnSHVMqK74T0"))
        #expect(!PadPlaybackAuthors.isParticipant("-Oxgyokn0gQK1wOpGQB-"))
        #expect(!PadPlaybackAuthors.isParticipant(""))
        // A short dash-prefixed name is not push-id shaped.
        #expect(PadPlaybackAuthors.isParticipant("-Ana"))
    }
}
