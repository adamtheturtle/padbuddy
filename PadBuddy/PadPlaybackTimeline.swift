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

    var id: String {
        "\(fileID)#\(snapshotIndex)"
    }
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
    /// Each participant's position in `participantAuthors`. The playback view asks
    /// for an author's lane ordinal and palette color once per lane *and* for the
    /// cursor on every playhead change, so answering with `firstIndex(of:)` made a
    /// many-participant session pay repeated linear scans per frame (#2094).
    let participantIndex: [String: Int]
    /// Precomputed identity for the scrubber's static drawing layer. Comparing
    /// whole timelines on every playhead tick walks every edit; this is computed
    /// once when the timeline is built and keeps the per-frame equality check O(1).
    let trackRenderKey: Int
    /// Visual time offsets cap long inactive intervals so active interview work
    /// remains scrubbable without changing the real elapsed-time readout.
    let displayOffsets: [Int64]
    let displayDuration: Int64
    let compressedGaps: [CompressedGap]

    static let maximumDisplayGapMilliseconds: Int64 = 5 * 60 * 1000

    struct CompressedGap: Hashable {
        let afterIndex: Int
        let fraction: Double
        let actualSeconds: Double
    }

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
    static let timestampRange: ClosedRange<Int64> = 0 ... 32_503_680_000_000

    init(histories: [PadFileHistory]) {
        let merged = Self.mergedItems(from: histories)
        items = merged

        let displayMapping = Self.displayMapping(for: items)
        displayOffsets = displayMapping.offsets
        displayDuration = displayMapping.duration
        compressedGaps = displayMapping.compressedGaps

        var seen = Set<String>()
        var ordered: [String] = []
        for item in items where seen.insert(item.author).inserted {
            ordered.append(item.author)
        }
        authors = ordered
        let participants = ordered.filter(PadPlaybackAuthors.isParticipant)
        participantAuthors = participants
        // `ordered` is already de-duplicated, so no key can repeat; the non-trapping
        // initializer is used anyway rather than betting a crash on that (#2497).
        participantIndex = Dictionary(participants.enumerated().map { ($0.element, $0.offset) },
                                      uniquingKeysWith: { first, _ in first })

        var hasher = Hasher()
        hasher.combine(items.count)
        hasher.combine(items.first?.timestamp ?? 0)
        hasher.combine(items.last?.timestamp ?? 0)
        for item in items {
            hasher.combine(item.fileID)
            hasher.combine(item.snapshotIndex)
            hasher.combine(item.timestamp)
            hasher.combine(item.author)
        }
        for author in authors {
            hasher.combine(author)
        }
        trackRenderKey = hasher.finalize()

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

    var startTimestamp: Int64 {
        items.first?.timestamp ?? 0
    }

    var endTimestamp: Int64 {
        items.last?.timestamp ?? 0
    }

    /// Wall-clock length of the session's edit history.
    var durationSeconds: Double {
        Double(endTimestamp - startTimestamp) / 1000
    }

    /// Seconds of session time between an item and its successor, never negative.
    func gapSeconds(after index: Int) -> Double {
        guard items.indices.contains(index), index + 1 < items.count else { return 0 }

        return max(0, Double(items[index + 1].timestamp - items[index].timestamp) / 1000)
    }

    /// Session-relative seconds elapsed at an item, for the time readout.
    func elapsedSeconds(at index: Int) -> Double {
        guard items.indices.contains(index) else { return 0 }

        return max(0, Double(items[index].timestamp - startTimestamp) / 1000)
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

    /// Whether `author` is one of the session's participants (rather than a
    /// template or upload seed), answered from `participantIndex` (#2094).
    func isParticipant(_ author: String) -> Bool {
        participantIndex[author] != nil
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
        let bytes = raw.utf8
        return bytes.count == 20 && bytes.first == UInt8(ascii: "-") && bytes.allSatisfy(isIDByte)
    }

    /// Whether a byte belongs to the backend's id charset (`[A-Za-z0-9_-]`).
    ///
    /// These checks used `range(of:options:.regularExpression)`, which compiled a
    /// fresh regex on every call — and they run per author while the timeline is
    /// built, then several times per frame during playback (#2091). The patterns
    /// were all plain ASCII character classes, so matching the bytes directly is
    /// both equivalent and free of any compilation.
    private static func isIDByte(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "a") ... UInt8(ascii: "z"),
             UInt8(ascii: "A") ... UInt8(ascii: "Z"),
             UInt8(ascii: "0") ... UInt8(ascii: "9"),
             UInt8(ascii: "_"), UInt8(ascii: "-"):
            true
        default:
            false
        }
    }

    private static func isASCIILetter(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "a") ... UInt8(ascii: "z"), UInt8(ascii: "A") ... UInt8(ascii: "Z"):
            true
        default:
            false
        }
    }

    private static func isASCIIDigit(_ byte: UInt8) -> Bool {
        UInt8(ascii: "0") ... UInt8(ascii: "9") ~= byte
    }

    /// Whether an author represents a session participant: a named author or an
    /// anonymous editor connection, as opposed to template or upload seeding.
    static func isParticipant(_ raw: String) -> Bool {
        let author = strippingInvisibles(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        return !author.isEmpty && author != systemAuthor && !isPushID(author)
    }

    /// The identity that two spellings of one author share.
    ///
    /// `isParticipant` already trimmed before deciding and `displayName` renders
    /// both identically, but the timeline keyed its lanes, palette colours, and
    /// position index on the raw value — so `"Alice"` and `"Alice "` became two
    /// participants with two lanes and two sets of positions (#4795). Case-folded
    /// for the reason `PadEventGrouping.actorKey(for:)` is: `Alice` and `alice` are
    /// one display identity, and keeping their case split their runs (#2002).
    static func identityKey(_ raw: String) -> String {
        strippingInvisibles(raw).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// `raw` without Unicode format (`Cf`) or control scalars.
    ///
    /// A display name is floated over another participant's code as the playback
    /// cursor tag, and history authors are untrusted backend identifiers, so a bidi
    /// override or isolate in one could reverse or reorder what is rendered there.
    /// Every comparable sanitizer in the project drops this category —
    /// `MCPActivityLog.isSafeLogScalar`, `normalizedCompanionTitle`,
    /// `MarkdownText.containsInvisibleURLScalar` — and this one did not (#4794).
    static func strippingInvisibles(_ raw: String) -> String {
        guard raw.unicodeScalars.contains(where: isInvisibleScalar) else { return raw }

        var scalars = String.UnicodeScalarView()
        for scalar in raw.unicodeScalars where !isInvisibleScalar(scalar) {
            scalars.append(scalar)
        }
        return String(scalars)
    }

    private static func isInvisibleScalar(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.generalCategory == .format
            || CharacterSet.controlCharacters.contains(scalar)
    }

    /// A raw history author, filtered down to something worth showing: numeric
    /// or letterless connection ids, upload push ids, and machine-token shapes
    /// return nil so the UI falls back to its anonymized "Participant N" label.
    static func displayName(_ raw: String) -> String? {
        let author = strippingInvisibles(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        let bytes = author.utf8
        // History authors are untrusted backend identifiers, not verified profile
        // names. Never surface address- or URL-shaped values in the playback header;
        // those can expose an email, connection endpoint, or opaque identity token.
        // The lane still exists, under its stable anonymized "Participant N" label.
        guard !author.isEmpty, author.count < 80 else { return nil }
        guard bytes.contains(where: isASCIILetter) else { return nil }
        guard !isPushID(author) else { return nil }
        guard !author.contains("@"), !author.contains(":"),
              !author.contains("/"), !author.contains("\\") else { return nil }

        // A long unbroken id-charset run is a backend connection token, not a
        // person's name — letters alone don't make it displayable (#1170).
        let tokenShape = bytes.count >= 16 && bytes.allSatisfy(isIDByte)
        let hasDigit = bytes.contains(where: isASCIIDigit)
        if tokenShape, hasDigit || author.count >= 24 {
            return nil
        }
        return author
    }
}
