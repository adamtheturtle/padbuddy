//
//  PadBuddyTests+PlaybackAuthorsAndTimestamps.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

private func edit(_ id: String, by author: String, at timestamp: Int64) -> PadHistoryEntry {
    PadHistoryEntry(id: id, author: author, operations: [.insert("x")], timestamp: timestamp)
}

private func makeFile(_ id: String, entries: [PadHistoryEntry]) -> PadFileHistory {
    PadFileHistory(id: id, title: "\(id).py", language: "python", history: PadHistory(entries: entries))
}

@Suite("Playback author sanitizing")
struct PlaybackAuthorSanitizingTests {
    /// The display name is floated over another participant's code as the cursor
    /// tag, so a bidi override in an untrusted backend author id could reorder what
    /// is rendered there (#4794).
    @Test func `bidi and format scalars are stripped from a display name`() {
        #expect(PadPlaybackAuthors.displayName("Ali\u{202E}ce") == "Alice")
        #expect(PadPlaybackAuthors.displayName("\u{2066}Basil\u{2069}") == "Basil")
        #expect(PadPlaybackAuthors.displayName("Syb\u{200B}il") == "Sybil")
    }

    @Test func `a name made only of invisibles is not displayable`() {
        #expect(PadPlaybackAuthors.displayName("\u{202E}\u{200B}") == nil)
    }

    @Test func `an ordinary name is untouched`() {
        #expect(PadPlaybackAuthors.displayName("Basil Fawlty") == "Basil Fawlty")
    }

    /// Stripping must not turn a rejected shape into an accepted one.
    @Test func `an address-shaped name is still rejected once stripped`() {
        #expect(PadPlaybackAuthors.displayName("basil\u{202E}@example.com") == nil)
    }

    @Test func `whitespace and case variants share one identity`() {
        let key = PadPlaybackAuthors.identityKey("Alice")

        #expect(PadPlaybackAuthors.identityKey("Alice ") == key)
        #expect(PadPlaybackAuthors.identityKey("  alice") == key)
        #expect(PadPlaybackAuthors.identityKey("Ali\u{202E}ce") == key)
        #expect(PadPlaybackAuthors.identityKey("Bob") != key)
    }

    /// The whitespace variant used to produce a second lane, a second palette
    /// colour, and a second set of positions (#4795).
    @Test func `the timeline gives one author one lane`() {
        let timeline = PadPlaybackTimeline(histories: [
            makeFile("main", entries: [
                edit("a", by: "Alice", at: 1000),
                edit("b", by: "Alice ", at: 2000),
                edit("c", by: "alice", at: 3000)
            ])
        ])

        #expect(timeline.authors.count == 1)
        #expect(timeline.participantAuthors == ["Alice"])
        #expect(timeline.authorPositions["Alice"]?.count == 3)
    }
}

@Suite("Playback timestamp plausibility")
struct PlaybackTimestampTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func timestamps(_ entries: [PadHistoryEntry]) -> [Int64] {
        PadPlaybackTimeline.mergedItems(from: [makeFile("main", entries: entries)], now: now)
            .map(\.timestamp)
    }

    /// `PadHistory` sorts its entries, so a far-future stamp lands last in its file
    /// and is pinned to its predecessor rather than extending the timeline's extent
    /// to the year-3000 clamp ceiling (#4797).
    @Test func `a future-stamped snapshot is pinned to its predecessor`() {
        let stamps = timestamps([
            edit("a", by: "Alice", at: 1_699_000_000_000),
            edit("b", by: "Alice", at: 32_000_000_000_000),
            edit("c", by: "Alice", at: 1_699_000_100_000)
        ])

        #expect(stamps == [1_699_000_000_000, 1_699_000_100_000, 1_699_000_100_000])
    }

    @Test func `a leading future stamp starts the file at its first usable one`() {
        let stamps = PadPlaybackTimeline.mergedItems(
            from: [makeFile("main", entries: [edit("a", by: "Alice", at: 32_000_000_000_000)])],
            now: now
        ).map(\.timestamp)

        #expect(stamps == [0])
    }

    /// Ordinary skew between the device and the backend is still accepted.
    @Test func `a stamp inside the tolerance is kept`() {
        let slightlyAhead = Int64(now.timeIntervalSince1970 * 1000) + 60000

        #expect(timestamps([edit("a", by: "Alice", at: slightlyAhead)]) == [slightlyAhead])
    }

    /// A negative stamp still clamps into the accepted range rather than trapping the
    /// interval arithmetic downstream (#1163).
    @Test func `a negative stamp is clamped, not dropped`() {
        #expect(timestamps([
            edit("a", by: "Alice", at: Int64.min),
            edit("b", by: "Alice", at: 1_699_000_000_000)
        ]) == [0, 1_699_000_000_000])
    }
}

@Suite("Zero-duration playback scrubbing")
struct ZeroDurationScrubTests {
    private var identical: PadPlaybackTimeline {
        PadPlaybackTimeline(histories: [
            makeFile("main", entries: (0 ..< 4).map { edit("e\($0)", by: "Alice", at: 1000) })
        ])
    }

    /// Rounding returned the edit *after* the point scrubbed to, against the
    /// documented "last edit at or before" contract (#4800).
    @Test func `scrubbing floors to the edit at or before the point`() {
        let timeline = identical

        #expect(timeline.displayDuration == 0)
        #expect(timeline.index(atFraction: 0) == 0)
        // Just short of the second edit's own fraction (1/3).
        #expect(timeline.index(atFraction: 0.33) == 0)
        #expect(timeline.index(atFraction: 0.34) == 1)
        #expect(timeline.index(atFraction: 1) == 3)
    }

    @Test func `index and fraction round-trip`() {
        let timeline = identical

        for index in 0 ..< 4 {
            #expect(timeline.index(atFraction: timeline.fraction(at: index)) == index)
        }
    }

    @Test func `an out-of-range fraction stays in bounds`() {
        let timeline = identical

        #expect(timeline.index(atFraction: -1) == 0)
        #expect(timeline.index(atFraction: 2) == 3)
    }
}
