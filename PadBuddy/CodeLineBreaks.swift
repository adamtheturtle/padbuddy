//
//  CodeLineBreaks.swift
//  coderpad
//
//  One definition of "line break" for code the app both measures and renders.
//

import Foundation

/// Splitting source on `"\n"` alone disagrees with how the text is actually drawn:
/// CoreText breaks a paragraph on CR as well as LF, on CRLF as a single break, and on the
/// Unicode separators. Classic Mac CR-only source therefore measured as one line while it
/// rendered as many, putting the playback caret and the estimated height on the wrong line
/// (#4564). These helpers use the platform's own `CharacterSet.newlines` so measurement and
/// rendering agree.
nonisolated enum CodeLineBreaks {
    static func isBreak(_ scalar: Unicode.Scalar) -> Bool {
        CharacterSet.newlines.contains(scalar)
    }

    /// Every line, empty ones included, with CRLF treated as a single break.
    static func lines(_ contents: String) -> [Substring] {
        var lines: [Substring] = []
        var lineStart = contents.startIndex
        var index = contents.startIndex
        while index < contents.endIndex {
            guard let scalar = contents[index].unicodeScalars.first, isBreak(scalar) else {
                index = contents.index(after: index)
                continue
            }

            lines.append(contents[lineStart ..< index])
            // A CRLF is one `Character`, so `index(after:)` already steps over both.
            index = contents.index(after: index)
            lineStart = index
        }
        lines.append(contents[lineStart...])
        return lines
    }

    /// How many breaks appear before the end of `contents` — that is, the zero-based line
    /// number the text after it sits on.
    static func breakCount(_ contents: some StringProtocol) -> Int {
        var count = 0
        for character in contents where character.unicodeScalars.first.map(isBreak) == true {
            count += 1
        }
        return count
    }

    /// The start of the last line in `contents`, for measuring the prefix before a caret.
    static func lastLineStart(_ contents: Substring) -> Substring.Index {
        var lineStart = contents.startIndex
        var index = contents.startIndex
        while index < contents.endIndex {
            let next = contents.index(after: index)
            if let scalar = contents[index].unicodeScalars.first, isBreak(scalar) {
                lineStart = next
            }
            index = next
        }
        return lineStart
    }

    /// UTF-16 offsets at which each line starts, for callers already working in UTF-16
    /// coordinates. Always begins with `0`.
    static func lineStartUTF16Offsets(
        // swiftlint:disable:next legacy_objc_type
        in contents: NSString
    ) -> [Int] {
        var starts = [0]
        starts.reserveCapacity(min(256, contents.length / 24 + 1))
        var searchStart = 0
        while searchStart < contents.length {
            let range = NSRange(location: searchStart, length: contents.length - searchStart)
            let found = contents.rangeOfCharacter(from: .newlines, options: [], range: range)
            guard found.location != NSNotFound else { break }

            var next = found.location + found.length
            // CRLF is one break; without this the LF opened a spurious empty line.
            if contents.character(at: found.location) == 13, next < contents.length,
               contents.character(at: next) == 10 {
                next += 1
            }
            searchStart = next
            starts.append(searchStart)
        }
        return starts
    }
}
