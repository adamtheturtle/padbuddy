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
                edit("a", by: "Basil", at: 1000), edit("b", by: "Basil", at: 5000)
            ]),
            makeFile("util", title: "util.py", entries: [
                edit("c", by: "Sybil", at: 3000)
            ])
        ])
    }

    @Test
    func `merges edits across files in chronological order`() {
        let timeline = interleaved

        #expect(timeline.items.map(\.fileID) == ["main", "util", "main"])
        #expect(timeline.items.map(\.timestamp) == [1000, 3000, 5000])
        #expect(timeline.items.map(\.snapshotIndex) == [0, 0, 1])
    }

    @Test
    func `authors are listed in order of first edit`() {
        #expect(interleaved.authors == ["Basil", "Sybil"])
        #expect(interleaved.participantAuthors == ["Basil", "Sybil"])
    }

    /// The lane ordinals and palette colors read from this index instead of
    /// scanning `participantAuthors` per lookup (#2094), so it has to agree with
    /// the array it replaces — including on authors that aren't participants.
    @Test
    func `the participant index matches the participant order`() {
        #expect(interleaved.participantIndex == ["Basil": 0, "Sybil": 1])
        #expect(interleaved.isParticipant("Basil"))
        #expect(!interleaved.isParticipant("CoderPad"))
    }

    /// A realistic session: CoderPad seeds the template files, a bulk upload
    /// stamps each file with a one-shot Firebase push id, and one anonymous
    /// connection does the actual typing. Only that connection is a participant.
    @Test
    func `template and upload seeds are not participants`() {
        let timeline = PadPlaybackTimeline(histories: [
            makeFile("main", title: "main.py", entries: [
                edit("a", by: "CoderPad", at: 1000),
                edit("b", by: "4503601411610331", at: 5000),
                edit("c", by: "4503601411610331", at: 6000)
            ]),
            makeFile("paper", title: "main.tex", entries: [
                edit("d", by: "-OxgyokRDnSHVMqK74T0", at: 2000)
            ]),
            makeFile("bib", title: "bib.bib", entries: [
                edit("e", by: "-OxgyoikD2X41FKTCSWo", at: 2100)
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
    func `long idle gaps are compressed without breaking scrub mapping`() {
        let hour: Int64 = 60 * 60 * 1000
        let timeline = PadPlaybackTimeline(histories: [
            makeFile("main", title: "main.py", entries: [
                edit("seed", by: "CoderPad", at: 1000),
                edit("joined", by: "Basil", at: 3 * hour + 1000),
                edit("working", by: "Basil", at: 3 * hour + 15 * 60 * 1000 + 1000),
                edit("done", by: "Basil", at: 3 * hour + 30 * 60 * 1000 + 1000)
            ])
        ])

        #expect(timeline.compressedGaps.count == 1)
        #expect(timeline.fraction(at: 1) < 0.2)
        #expect(timeline.fraction(at: 3) - timeline.fraction(at: 1) > 0.8)
        for index in timeline.items.indices {
            #expect(timeline.index(atFraction: timeline.fraction(at: index)) == index)
        }
        let fractions = timeline.items.indices.map(timeline.fraction)
        #expect(fractions == fractions.sorted())
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

    /// Same-millisecond edits in different files order by file id, so an API
    /// reload that reorders the files replays identically (#1880).
    @Test
    func `same-millisecond cross-file edits order by file id, not array order`() {
        let fileA = makeFile("alpha", title: "a.py", entries: [edit("a", by: "Basil", at: 1000)])
        let fileB = makeFile("beta", title: "b.py", entries: [edit("b", by: "Sybil", at: 1000)])

        let forward = PadPlaybackTimeline(histories: [fileA, fileB])
        let reversed = PadPlaybackTimeline(histories: [fileB, fileA])

        #expect(forward.items.map(\.fileID) == ["alpha", "beta"])
        #expect(forward.items == reversed.items)
    }

    /// Clock skew in the feed: entries whose timestamps go backwards still
    /// produce a timeline whose timestamps never decrease, so playback can't
    /// show a later snapshot of a file before an earlier one (#1879).
    /// `PadHistory` sorts its entries on construction and the timeline lifts
    /// any timestamp below its per-file predecessor as a second guard.
    @Test
    func `out-of-order feed timestamps still yield a non-decreasing timeline`() {
        let timeline = PadPlaybackTimeline(histories: [
            makeFile("main", title: "main.py", entries: [
                edit("b", by: "Basil", at: 5000), edit("a", by: "Basil", at: 3000)
            ])
        ])

        #expect(timeline.items.map(\.timestamp) == [3000, 5000])
        #expect(timeline.items.map(\.snapshotIndex) == [0, 1])
        #expect(timeline.items.map(\.timestamp) == timeline.items.map(\.timestamp).sorted())
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

        #expect(timeline.fraction(atMilliseconds: 3000) == 0.5)
        #expect(timeline.fraction(atMilliseconds: 500) == nil)
        #expect(timeline.fraction(atMilliseconds: 9000) == nil)
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

@Suite("Playback frame coalescing")
struct PlaybackFrameCoalescingTests {
    @Test
    func `same-millisecond edit bursts advance in one rendered frame`() {
        let timeline = PadPlaybackTimeline(histories: [
            makeFile("main", title: "main.py", entries: [
                edit("a", by: "Basil", at: 1000),
                edit("b", by: "Basil", at: 1000),
                edit("c", by: "Basil", at: 1000),
                edit("d", by: "Basil", at: 1000)
            ])
        ])

        let advance = HistoryPlaybackView.playbackAdvance(timeline: timeline, from: 0)

        #expect(advance.position == 3)
        #expect(advance.delay == HistoryPlaybackView.minPlaybackStep)
    }

    @Test
    func `coalescing never crosses a visible pause`() {
        let timeline = PadPlaybackTimeline(histories: [
            makeFile("main", title: "main.py", entries: [
                edit("a", by: "Basil", at: 1000),
                edit("b", by: "Basil", at: 1000),
                edit("c", by: "Basil", at: 2000)
            ])
        ])

        let burst = HistoryPlaybackView.playbackAdvance(timeline: timeline, from: 0)
        let pause = HistoryPlaybackView.playbackAdvance(timeline: timeline, from: 1)

        #expect(burst.position == 1)
        #expect(pause.position == 2)
        #expect(pause.delay == 1)
    }
}

@Suite("Playback participant names")
struct PlaybackParticipantNameTests {
    @Test
    func `anonymous lanes never guess identities from participant order`() {
        let names = HistoryPlaybackView.participantNameMap(
            authors: ["Basil", "4503601411610331", "9988776655443322"],
            names: ["Basil", "Sybil", "Ada"]
        )

        #expect(names["Basil"] == "Basil")
        #expect(names["4503601411610331"] == nil)
        #expect(names["9988776655443322"] == nil)
    }

    @Test
    func `missing and duplicate names leave unmatched lanes anonymous`() {
        let names = HistoryPlaybackView.participantNameMap(
            authors: ["1111111111111111", "2222222222222222"],
            names: [" Ada ", "ada", ""]
        )

        #expect(names["1111111111111111"] == nil)
        #expect(names["2222222222222222"] == nil)
    }
}

/// The scrubber's run markers, now computed once per events/timeline change
/// rather than on every playback tick (#2090).
struct PadPlaybackRunMarkerTests {
    private let timeline = PadPlaybackTimeline(histories: [
        makeFile("main", title: "main.py", entries: [
            edit("a", by: "Basil", at: 1000), edit("b", by: "Basil", at: 5000)
        ])
    ])

    private func event(_ kind: String, at milliseconds: Double?) -> PadEvent {
        PadEvent(
            message: "m",
            kind: kind,
            createdAt: milliseconds.map { Date(timeIntervalSince1970: $0 / 1000) }
        )
    }

    @Test
    func `only runs inside the timeline get a marker`() {
        let markers = HistoryPlaybackView.runMarkers(
            events: [
                event("ran", at: 1000),
                event("joined", at: 3000),
                event("executed", at: 5000),
                // Outside the session, undated, and past the sane date range.
                event("ran", at: 9000),
                event("ran", at: nil),
                event("ran", at: -1_000_000_000_000_000)
            ],
            timeline: timeline
        )
        #expect(markers == [0, 1])
    }

    @Test
    func `runs in the same rendered bucket are drawn once`() {
        let markers = HistoryPlaybackView.runMarkers(
            events: [event("ran", at: 3000), event("RAN", at: 3001)],
            timeline: timeline
        )
        #expect(markers.count == 1)
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
        #expect(PadPlaybackAuthors.displayName("candidate@example.com") == nil)
        #expect(PadPlaybackAuthors.displayName("connection://candidate") == nil)
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

    /// The classification is byte-wise rather than regex-driven (#2091), so pin
    /// the edges the character classes decide: accented names still read as
    /// names, non-ASCII-only ones don't, and token shape counts characters.
    @Test
    func `classification survives non-ASCII and token-shaped authors`() {
        #expect(PadPlaybackAuthors.displayName("Renée Dubois") == "Renée Dubois")
        #expect(PadPlaybackAuthors.displayName("Jean-Luc") == "Jean-Luc")
        #expect(PadPlaybackAuthors.displayName("日本語") == nil)
        // Sixteen id characters with a digit is a connection token, not a name.
        #expect(PadPlaybackAuthors.displayName("abcdef0123456789") == nil)
        #expect(PadPlaybackAuthors.displayName("Manuel-the-waiter") == "Manuel-the-waiter")
        #expect(!PadPlaybackAuthors.isPushID("-OxgyokRDnSHVMqK74T"))
        #expect(PadPlaybackAuthors.isPushID("-OxgyokRDnSHVMqK74T0"))
    }
}
