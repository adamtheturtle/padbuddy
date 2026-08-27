//
//  PadCodePreview+PlaybackCursor.swift
//  coderpad
//
//  Exact caret positioning for history playback.
//

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif
import SwiftUI

extension HighlightedCode {
    /// Measures the current line prefix with the same monospaced font as the
    /// source. Measuring instead of multiplying a character count handles tabs,
    /// composed characters, and non-ASCII source without drifting horizontally.
    var cursorPoint: CGPoint? {
        guard let cursorOffset else { return nil }

        let utf16 = contents.utf16
        let bounded = min(max(0, cursorOffset), utf16.count)
        // Walking the UTF-16 view keeps this off the O(file size) `Array(contents.utf16)`
        // copy playback was paying on every tick, for a caret that only ever needs the
        // text before it (#4565).
        let caret = characterBoundary(atUTF16Offset: bounded, in: contents)
        let prefix = contents[..<caret]
        let linePrefix = prefix[CodeLineBreaks.lastLineStart(prefix)...]

        let width = NSAttributedString(
            string: String(linePrefix),
            attributes: [.font: platformCodeFont(scale: fontScale)]
        ).size().width
        return CGPoint(x: ceil(width), y: CGFloat(CodeLineBreaks.breakCount(prefix)) * lineHeight)
    }

    /// Rounds a UTF-16 offset down to a `Character` boundary. A history cursor offset can
    /// land inside a surrogate pair or a composed cluster, and decoding across one repairs
    /// it with U+FFFD — whose measured width is not the width of the text actually before
    /// the caret, putting it at the wrong column (#4563).
    private func characterBoundary(atUTF16Offset offset: Int, in string: String) -> String.Index {
        let utf16 = string.utf16
        var probe = utf16.index(utf16.startIndex, offsetBy: offset)
        while true {
            if let aligned = probe.samePosition(in: string) {
                return aligned
            }

            guard probe > utf16.startIndex else { return string.startIndex }

            probe = utf16.index(before: probe)
        }
    }
}
