//
//  PadPlaybackTimeline.swift
//  coderpad
//
//  The model behind the History card's session playback: every file's edits
//  merged into one chronological timeline, plus the time arithmetic playback
//  needs. The views live in PadHistoryPlayback.swift.
//

import Foundation

/// A single edit on the unified playback timeline: one snapshot of one file,
/// ordered chronologically across every file in the pad.
nonisolated struct PadPlaybackItem: Identifiable, Hashable {
    let fileID: String
    let snapshotIndex: Int
    /// Milliseconds since the Unix epoch, as supplied by the history feed.
    let timestamp: Int64
    let author: String

    var id: String { "\(fileID)#\(snapshotIndex)" }
}

/// The pad's edits merged across files into one chronological sequence, with
/// the time arithmetic playback needs: mapping edits to 0...1 positions on a
/// wall-clock-proportional track and back, gap lengths for real-time pacing,
/// and per-file lookups so any file's state can be shown for a given playhead.
nonisolated struct PadPlaybackTimeline: Hashable {
    let items: [PadPlaybackItem]
    /// Raw author identifiers in order of first edit, seeds included.
    let authors: [String]
    /// The authors who are actually people (named authors and anonymous editor
    /// connections), in order of first edit. Template and file-upload seeds are
    /// excluded: a bulk upload stamps every file with a fresh Firebase push id,
    /// which would otherwise read as dozens of participants.
    let participantAuthors: [String]

    /// One file item's place on the timeline, for the per-file lookup index.
    struct SnapshotRef: Hashable {
        let position: Int
        let snapshotIndex: Int
    }

    /// Item positions per author, ascending, so activity lanes and lane jumps
    /// read one author's edits directly instead of scanning the whole timeline
    /// per author (#1872, #1883).
    let authorPositions: [String: [Int]]
    /// Each file's items in playhead order, so the visible-snapshot lookup is a
    /// binary search rather than a linear walk per rendered playhead (#1871).
    private let filePositions: [String: [SnapshotRef]]

    /// The largest epoch-milliseconds value the timeline accepts (year 3000).
    /// History timestamps are remote data: extreme values like `Int64.min`/`max`
    /// would overflow the interval arithmetic below and trap while opening
    /// History, so every timestamp is clamped into this range (#1163).
    static let timestampRange: ClosedRange<Int64> = 0...32_503_680_000_000

    init(histories: [PadFileHistory]) {
        // Items and per-file snapshot lookups are keyed by file id; a malformed
        // pad returning duplicate ids would give items colliding identities and
        // let `snapshotIndex(of:at:)` select the other file's edit, so only each
        // id's first history is merged (#1165) — matching the playback view,
        // which also resolves a file id to its first history.
        var seenIDs = Set<String>()
        let uniqueHistories = histories.filter { seenIDs.insert($0.id).inserted }

        var merged: [PadPlaybackItem] = []
        for history in uniqueHistories {
            // A file's snapshots are causally ordered; a timestamp that goes
            // backwards mid-file (clock skew in the feed) is lifted to its
            // predecessor so playback can never show a later snapshot before an
            // earlier one of the same file (#1879).
            var previousTimestamp = Self.timestampRange.lowerBound
            for snapshot in history.snapshots {
                let clamped = min(max(snapshot.entry.timestamp, Self.timestampRange.lowerBound),
                                  Self.timestampRange.upperBound)
                let monotonic = max(clamped, previousTimestamp)
                previousTimestamp = monotonic
                merged.append(PadPlaybackItem(
                    fileID: history.id,
                    snapshotIndex: snapshot.index,
                    timestamp: monotonic,
                    author: snapshot.entry.author
                ))
            }
        }
        // Explicit tie-breakers rather than relying on sort stability: edits in
        // the same millisecond order by file id, then per-file edit order. The
        // id, not the array position, so an API reload that reorders the files
        // replays the same edits in the same sequence (#1880).
        merged.sort {
            ($0.timestamp, $0.fileID, $0.snapshotIndex)
                < ($1.timestamp, $1.fileID, $1.snapshotIndex)
        }
        items = merged

        var seen = Set<String>()
        var ordered: [String] = []
        for item in items where seen.insert(item.author).inserted {
            ordered.append(item.author)
        }
        authors = ordered
        participantAuthors = ordered.filter(PadPlaybackAuthors.isParticipant)

        var byAuthor: [String: [Int]] = [:]
        var byFile: [String: [SnapshotRef]] = [:]
        for (position, item) in items.enumerated() {
            byAuthor[item.author, default: []].append(position)
            byFile[item.fileID, default: []]
                .append(SnapshotRef(position: position, snapshotIndex: item.snapshotIndex))
        }
        authorPositions = byAuthor
        filePositions = byFile
    }

    var startTimestamp: Int64 { items.first?.timestamp ?? 0 }
    var endTimestamp: Int64 { items.last?.timestamp ?? 0 }

    /// Wall-clock length of the session's edit history.
    var durationSeconds: Double {
        Double(endTimestamp - startTimestamp) / 1_000
    }

    /// Where an item sits on the track, 0...1, proportional to session time so
    /// the scrubber reads like a video timeline. Falls back to even index
    /// spacing when every edit shares one timestamp.
    func fraction(at index: Int) -> Double {
        guard items.count > 1, items.indices.contains(index) else { return 0 }
        guard endTimestamp > startTimestamp else {
            return Double(index) / Double(items.count - 1)
        }
        return Double(items[index].timestamp - startTimestamp)
            / Double(endTimestamp - startTimestamp)
    }

    /// Where a raw millisecond instant sits on the track, or nil when it falls
    /// outside the session (or the session has no wall-clock extent).
    func fraction(atMilliseconds milliseconds: Int64) -> Double? {
        guard endTimestamp > startTimestamp else { return nil }
        guard milliseconds >= startTimestamp, milliseconds <= endTimestamp else { return nil }
        return Double(milliseconds - startTimestamp) / Double(endTimestamp - startTimestamp)
    }

    /// The item the playhead lands on when dropped at `fraction`: the last edit
    /// at or before that moment, so scrubbing shows what the pad looked like then.
    func index(atFraction fraction: Double) -> Int {
        guard items.count > 1 else { return 0 }
        let clamped = min(max(fraction, 0), 1)
        guard endTimestamp > startTimestamp else {
            return Int((clamped * Double(items.count - 1)).rounded())
        }
        let target = startTimestamp
            + Int64((clamped * Double(endTimestamp - startTimestamp)).rounded())
        var low = 0
        var high = items.count - 1
        var result = 0
        while low <= high {
            let mid = (low + high) / 2
            if items[mid].timestamp <= target {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result
    }

    /// Seconds of session time between an item and its successor, never negative.
    func gapSeconds(after index: Int) -> Double {
        guard items.indices.contains(index), index + 1 < items.count else { return 0 }
        return max(0, Double(items[index + 1].timestamp - items[index].timestamp) / 1_000)
    }

    /// Session-relative seconds elapsed at an item, for the time readout.
    func elapsedSeconds(at index: Int) -> Double {
        guard items.indices.contains(index) else { return 0 }
        return max(0, Double(items[index].timestamp - startTimestamp) / 1_000)
    }

    /// The snapshot of `fileID` visible at the playhead: its most recent edit at
    /// or before position. Nil when the file hasn't been touched yet, so the UI
    /// can say so instead of showing the file's final contents out of time.
    /// Binary search over the file's own items, not a walk of the whole
    /// timeline, since this runs for every rendered playhead (#1871).
    func snapshotIndex(of fileID: String, at position: Int) -> Int? {
        guard items.indices.contains(position), let refs = filePositions[fileID] else { return nil }
        var low = 0
        var high = refs.count - 1
        var result: Int?
        while low <= high {
            let mid = (low + high) / 2
            if refs[mid].position <= position {
                result = refs[mid].snapshotIndex
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result
    }

    /// The edit by `author` closest in session time to `fraction`, so clicking
    /// a person's activity lane jumps to what they were doing there. Binary
    /// search over that author's own edits (#1883); ties keep the earlier edit.
    func index(ofAuthor author: String, nearestToFraction fraction: Double) -> Int? {
        guard let positions = authorPositions[author], !positions.isEmpty, !items.isEmpty else { return nil }

        let anchorTime = items[index(atFraction: fraction)].timestamp
        var low = 0
        var high = positions.count - 1
        while low < high {
            let mid = (low + high) / 2
            if items[positions[mid]].timestamp < anchorTime {
                low = mid + 1
            } else {
                high = mid
            }
        }
        var best = positions[low]
        if low > 0,
           abs(items[positions[low - 1]].timestamp - anchorTime)
           <= abs(items[best].timestamp - anchorTime) {
            best = positions[low - 1]
        }
        return best
    }
}

nonisolated enum PadPlaybackAuthors {
    /// The author CoderPad stamps on template seeds: the edits that populate a
    /// fresh pad's files before anyone types.
    static let systemAuthor = "CoderPad"

    /// Whether an author is a Firebase push id (a "-" followed by 19 id
    /// characters). Uploading files into a pad stamps each file's seed edit
    /// with a fresh push id, so these mark uploads, not people.
    static func isPushID(_ raw: String) -> Bool {
        raw.range(of: #"^-[A-Za-z0-9_-]{19}$"#, options: .regularExpression) != nil
    }

    /// Whether an author represents a session participant: a named author or an
    /// anonymous editor connection, as opposed to template or upload seeding.
    static func isParticipant(_ raw: String) -> Bool {
        let author = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return !author.isEmpty && author != systemAuthor && !isPushID(author)
    }

    /// A raw history author, filtered down to something worth showing: numeric
    /// or letterless connection ids, upload push ids, and machine-token shapes
    /// return nil so the UI falls back to its anonymized "Participant N" label.
    static func displayName(_ raw: String) -> String? {
        let author = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !author.isEmpty, author.count < 80 else { return nil }
        guard author.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil else { return nil }
        guard !isPushID(author) else { return nil }

        // A long unbroken id-charset run is a backend connection token, not a
        // person's name — letters alone don't make it displayable (#1170).
        let tokenShape = author.range(of: #"^[A-Za-z0-9_-]{16,}$"#, options: .regularExpression) != nil
        let hasDigit = author.range(of: #"[0-9]"#, options: .regularExpression) != nil
        if tokenShape, hasDigit || author.count >= 24 { return nil }
        return author
    }
}
