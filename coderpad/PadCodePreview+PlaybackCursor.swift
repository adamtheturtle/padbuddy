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

        let units = Array(contents.utf16)
        let bounded = min(max(0, cursorOffset), units.count)
        let prefix = units[..<bounded]
        let lineStart = prefix.lastIndex(of: 10).map { prefix.index(after: $0) } ?? prefix.startIndex
        let linePrefix = String(decoding: prefix[lineStart...], as: UTF16.self)

        #if os(macOS)
            let size = NSFont.preferredFont(forTextStyle: .callout).pointSize
            let font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
            let width = NSAttributedString(string: linePrefix, attributes: [.font: font]).size().width
        #else
            let size = UIFont.preferredFont(forTextStyle: .callout).pointSize
            let font = UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
            let width = NSAttributedString(string: linePrefix, attributes: [.font: font]).size().width
        #endif
        let line = prefix.reduce(into: 0) { count, unit in
            if unit == 10 { count += 1 }
        }
        return CGPoint(x: ceil(width), y: CGFloat(line) * Self.lineHeight)
    }
}
