//
//  CodeSearch.swift
//  coderpad
//

import Foundation

nonisolated enum CodeSearch {
    static func ranges(of query: String, in source: String) -> [Range<String.Index>] {
        guard !query.isEmpty else { return [] }

        var matches: [Range<String.Index>] = []
        var remaining = source.startIndex ..< source.endIndex
        while let match = source.range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive],
            range: remaining
        ) {
            matches.append(match)
            remaining = match.upperBound ..< source.endIndex
        }
        return matches
    }
}
