import Foundation

nonisolated enum CodeSearch {
    static let maximumSourceScalars = 200_000
    static let maximumQueryScalars = 256
    static let maximumMatches = 1000

    struct Highlights {
        let ranges: [Range<String.Index>]
        let isLimited: Bool
    }

    static func highlights(of query: String, in source: String) -> Highlights {
        guard !query.isEmpty else { return Highlights(ranges: [], isLimited: false) }

        // Refuse an oversized search before normalization, matching, or creating
        // another attributed copy of the file on the view's synchronous path.
        guard query.unicodeScalars.prefix(maximumQueryScalars + 1).count <= maximumQueryScalars,
              source.unicodeScalars.prefix(maximumSourceScalars + 1).count <= maximumSourceScalars
        else { return Highlights(ranges: [], isLimited: true) }

        var matches: [Range<String.Index>] = []
        var remaining = source.startIndex ..< source.endIndex
        while matches.count < maximumMatches, let match = source.range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive],
            range: remaining
        ) {
            matches.append(match)
            guard match.upperBound > remaining.lowerBound else { break }

            remaining = match.upperBound ..< source.endIndex
        }
        return Highlights(ranges: matches, isLimited: matches.count == maximumMatches)
    }
}
