//
//  PadCodePreview+HighlightedCode.swift
//  coderpad
//
//  The scrollable, syntax-highlighted single-file view used by the code cards
//  (see `EnvironmentCodeCard`). Split out of `PadCodePreview.swift` to keep each
//  file under the length limit.
//

// swiftlint:disable file_length

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif
import SwiftUI

/// The scrollable, syntax-highlighted view of one file's source. Kept separate
/// and `Equatable` so SwiftUI skips re-running the costly highlighter when the
/// enclosing card re-renders for unrelated reasons — most importantly while the
/// user drags the file sidebar's resize handle, which would otherwise re-tokenize
/// the whole file on every frame and make the drag stutter. `body` (and thus the
/// highlight pass) runs again only when the contents, language, or appearance
/// differ from the previous value.
struct HighlightedCode: View, Equatable { // swiftlint:disable:this type_body_length
    let contents: String
    let language: String?
    let dark: Bool
    /// When true the scroll fills whatever height it's given instead of pinning to
    /// 360. Only safe when this is the *outermost* vertical scroll (the full-screen
    /// viewer) — inside the detail pane's own vertical scroll the fixed height is
    /// what avoids the combinatorial re-measure hang (#494), so the card keeps it.
    var fillsHeight = false
    /// Fixed height for embedded code panes. Kept determinate to avoid nested-scroll
    /// layout feedback, but call sites with denser workflows can opt into more room.
    var embeddedViewportHeight: CGFloat = 360
    /// Scales the platform's preferred code font. Compact iPhone panes use a
    /// slightly denser size while preserving Dynamic Type's relative scaling.
    var fontScale: CGFloat = 1
    /// Search text whose every match is emphasized in the rendered source.
    var searchQuery = ""
    /// Adds a quiet inset backdrop when source is embedded as section content.
    var usesCodeWell = false
    /// A 0-based line to keep in view, scrolled to whenever it changes: session
    /// playback follows the line being edited (#983). Nil (every other call site)
    /// never scrolls programmatically.
    var focusLine: Int?
    /// UTF-16 insertion point for the playback participant's actual caret. Nil
    /// outside playback.
    var cursorOffset: Int?
    /// A name tag floated at `focusLine`, naming whose cursor the playback is
    /// following - like the web playback's participant cursor label (#985). Nil
    /// (every non-playback call site) draws nothing.
    var cursorLabel: String?
    /// Small identity for source changes that should re-center the focused line
    /// even when the line number itself is unchanged, such as history scrubbing.
    var scrollIdentity: String?
    /// The tag's background, matching the participant's timeline color (#985).
    var cursorColor: Color = .accentColor
    /// Rapid playback snapshots change faster than a full syntax pass can finish.
    /// Disabling the pass while playback runs keeps one stable presentation instead
    /// of flashing plain → highlighted after every pause (#2897).
    var allowsHighlighting = true
    /// Optional lightweight identity for rapid playback frames. Comparing the
    /// full source string in `Equatable` can dominate every playhead tick for large
    /// files; playback supplies a file/snapshot identity instead.
    var contentIdentity: String?
    /// A caller may prepare the current text off-main before publishing a rapid
    /// state transition (history playback). It wins only when its input and color
    /// scheme exactly match this view, so stale prepared text can never flash.
    var preparedHighlightedText: AttributedString?
    var preparedHighlightedContents: String?
    var preparedHighlightedDark: Bool?

    /// The highlighted result, filled in by an off-main pass; plain `contents`
    /// renders until it lands so the main thread isn't blocked tokenizing (#372).
    @State private var highlighted: AttributedString?

    /// The contents `highlighted` was produced from. This view keeps its identity
    /// when the user switches files (it sits at a fixed position in the card), so
    /// `highlighted` survives a switch holding the *previous* file's text; rendering
    /// checks this against `contents` so the new file's plain source shows
    /// immediately instead of the old file's highlighted source (#1042).
    @State private var highlightedContents: String?

    /// Whether the pointer is over the code block. On macOS the copy button only
    /// appears while hovering so it doesn't clutter the code at rest; on iPad,
    /// which has no hover, the button is always shown.
    @State private var isHovering = false

    /// Snap (not animate) the playback follow-scroll when Reduce Motion is on.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Reposition the followed line when the system text size changes while this
    /// code view remains mounted (#1891).
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Briefly flips the copy button to a checkmark after a successful copy, so a
    /// click gives visible confirmation. Reset after a short delay.
    @State private var didCopy = false
    @State private var copyGeneration = 0
    @State private var copyTask: Task<Void, Never>?
    @State private var copyResetTask: Task<Void, Never>?

    /// Where the scroll sits, so playback can move it to the edited line (#983).
    @State private var scrollPosition = ScrollPosition()

    /// Compare only the inputs (not the @State result) so SwiftUI keeps skipping
    /// re-renders for unrelated reasons, e.g. the file sidebar's resize drag.
    static func == (lhs: Self, rhs: Self) -> Bool {
        let usesIdentity = lhs.contentIdentity != nil && rhs.contentIdentity != nil
        let sameContents = if usesIdentity {
            lhs.contentIdentity == rhs.contentIdentity
        } else {
            lhs.contents == rhs.contents
        }
        let samePreparedContents = usesIdentity
            || lhs.preparedHighlightedContents == rhs.preparedHighlightedContents

        return sameContents && lhs.language == rhs.language
            && lhs.dark == rhs.dark && lhs.fillsHeight == rhs.fillsHeight
            && lhs.embeddedViewportHeight == rhs.embeddedViewportHeight
            && lhs.fontScale == rhs.fontScale
            && lhs.searchQuery == rhs.searchQuery
            && lhs.usesCodeWell == rhs.usesCodeWell
            && lhs.focusLine == rhs.focusLine
            && lhs.cursorOffset == rhs.cursorOffset
            && lhs.cursorLabel == rhs.cursorLabel && lhs.scrollIdentity == rhs.scrollIdentity
            && lhs.cursorColor == rhs.cursorColor
            && lhs.allowsHighlighting == rhs.allowsHighlighting
            && samePreparedContents
            && lhs.preparedHighlightedDark == rhs.preparedHighlightedDark
            && (lhs.preparedHighlightedText != nil) == (rhs.preparedHighlightedText != nil)
    }

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            ZStack(alignment: .topLeading) {
                playbackLineHighlight
                Text(displayText)
                    .font(codeFont)
                    .textSelection(.enabled)
                    // The visual source intentionally has no gutter, but VoiceOver
                    // users still need the same line coordinates used by playback
                    // and diagnostics. Present each logical line with its 1-based
                    // number without changing the text copied by selection (#3226).
                    .accessibilityLabel(accessibleSource)
                    // Keep source as one visual row per newline. On narrow iPhone
                    // widths, wrapping makes playback's logical-line overlay drift
                    // onto the wrong rendered row.
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                // Inside the scroll content (not the viewport), so the tag stays
                // glued to its line as the code scrolls (#985).
                playbackCursorOverlay
            }
        }
        .defaultScrollAnchor(.topLeading)
        .scrollPosition($scrollPosition)
        .onChange(of: ScrollTarget(
            line: focusLine,
            cursorOffset: cursorOffset,
            identity: scrollIdentity
        )) { _, newValue in
            scroll(toLine: newValue.line, animated: allowsHighlighting && !reduceMotion)
        }
        .onChange(of: dynamicTypeSize) {
            scroll(toLine: focusLine, animated: false)
        }
        .onAppear {
            scroll(toLine: focusLine, animated: false)
        }
        // A *determinate* height, not `maxHeight: 360`. This scroll is vertical and
        // lives inside the detail pane's own vertical scroll; a flexible `maxHeight`
        // range made the outer scroll re-measure this view's full (un-clamped) content
        // height on every layout probe to decide where in 0...360 it should land —
        // re-running CoreText text measurement combinatorially and beachballing the
        // main thread (#494). Pinning the height gives the nested scroll an unambiguous
        // size, so the outer scroll never renegotiates it; the code still scrolls in
        // both axes within this fixed viewport. The full-screen viewer opts into
        // `fillsHeight` because there it *is* the outer scroll, so there's nothing to
        // renegotiate against.
        .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
        .frame(height: fillsHeight ? nil : embeddedHeight(for: contents, maxHeight: embeddedViewportHeight))
        .background {
            if drawsCodeWell {
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(codeWellFill)
            }
        }
        .overlay {
            if drawsCodeWell {
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .stroke(codeWellStroke, lineWidth: 1)
            }
        }
        // The copy control sits inside the code block, pinned to the top-right
        // corner and floating above the source, the way GitHub and docs sites
        // place it. On macOS it fades in on hover so it stays out of the way when
        // reading; on iPad (no hover) it's always visible.
        .overlay(alignment: .topTrailing) {
            copyButton
                .padding(8)
        }
        #if os(macOS)
        .onHover { isHovering = $0 }
        #endif
        // A file switch means the copy confirmation (and any in-flight RTF write)
        // belongs to the previous file; reset so the checkmark can't linger over
        // code it didn't copy (#1042).
        .onChange(of: contents) {
            copyGeneration += 1
            copyTask?.cancel()
            copyResetTask?.cancel()
            didCopy = false
        }
        .onDisappear {
            // Invalidate the generation as well as cancelling: actor work may
            // finish after cancellation, and must not publish rich clipboard data
            // or feedback for a code view that no longer exists (#1914).
            copyGeneration += 1
            copyTask?.cancel()
            copyTask = nil
            copyResetTask?.cancel()
            copyResetTask = nil
            didCopy = false
        }
        // an unrelated re-render won't re-highlight.
        // an unrelated re-render will not re-highlight.
        .task(id: HighlightInput(
            contents: contents, language: language, dark: dark,
            allowsHighlighting: allowsHighlighting
        )) {
            guard allowsHighlighting else {
                return
            }

            // Let rapid keyboard/file-list movement settle before entering the
            // serial highlighter actor. Cancellation is cheap during this window,
            // unlike work already queued inside Highlightr (#1916).
            guard await HighlightScheduling.waitForSettledInput() else { return }

            let result = await SyntaxHighlighter.highlight(contents, language: language, dark: dark)
            // A restarted task (newer contents) cancels this one; dropping the stale
            // result keeps `highlighted` and `highlightedContents` in step.
            guard !Task.isCancelled else { return }

            highlighted = result
            highlightedContents = contents
        }
    }

    /// The rendered source: the highlighted pass only when it was produced from the
    /// *current* contents, else the plain text until the new pass lands (#1042).
    private var displayText: AttributedString {
        if !searchQuery.isEmpty {
            var result = AttributedString(contents)
            for sourceRange in CodeSearch.ranges(of: searchQuery, in: contents) {
                guard let lower = AttributedString.Index(sourceRange.lowerBound, within: result),
                      let upper = AttributedString.Index(sourceRange.upperBound, within: result) else { continue }

                result[lower ..< upper].backgroundColor = .yellow.opacity(0.45)
                result[lower ..< upper].foregroundColor = .primary
            }
            return result
        }
        if let preparedHighlightedText,
           preparedHighlightedContents == contents,
           preparedHighlightedDark == dark {
            return preparedHighlightedText
        }
        if let highlighted, highlightedContents == contents { return highlighted }
        return AttributedString(contents)
    }

    private var accessibleSource: String {
        contents.split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { "Line \($0.offset + 1), \($0.element)" }
            .joined(separator: "\n")
    }

    private var drawsCodeWell: Bool {
        #if os(visionOS)
            true
        #else
            usesCodeWell
        #endif
    }

    private var codeWellFill: Color {
        #if os(visionOS)
            dark ? Color.black : Color.white
        #else
            Color.cardBackground
        #endif
    }

    private var codeWellStroke: Color {
        #if os(visionOS)
            Color.secondary.opacity(dark ? 0.45 : 0.24)
        #else
            Color.subtleStroke
        #endif
    }

    /// the caret where the next character would be typed (#2905).
    @ViewBuilder
    private var playbackLineHighlight: some View {
        if let focusLine {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(cursorColor.opacity(dark ? 0.22 : 0.14))
                .frame(maxWidth: .infinity)
                .frame(height: lineHeight)
                .offset(y: 8 + CGFloat(focusLine) * lineHeight)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// The actual insertion caret and participant tag. CoderPad's OT operations
    /// address UTF-16 offsets, which lets playback put the caret where the next
    /// character would be typed (#2905).
    @ViewBuilder
    private var playbackCursorOverlay: some View {
        if focusLine != nil {
            ZStack(alignment: .topLeading) {
                if let point = cursorPoint {
                    Rectangle()
                        .fill(cursorColor)
                        .frame(width: 2, height: lineHeight)
                        .offset(x: 10 + point.x, y: 8 + point.y)
                }
                cursorTag
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// The floating participant name tag at the edited line - the playback
    /// counterpart of the web player's cursor label (#985). Decorative (the
    /// header and lanes already name the author accessibly), so it's hidden from
    /// VoiceOver and never intercepts clicks meant for the code.
    @ViewBuilder
    private var cursorTag: some View {
        if let cursorLabel, let focusLine {
            Text(cursorLabel)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                // An overlay is proposed only the source line's width. Refuse that
                // compression so a long participant name keeps the whole capsule
                // instead of clipping its trailing characters (#2910).
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(cursorColor.opacity(0.92), in: Capsule())
                // Sit just above the edited line (clamped so line 0 stays visible),
                // sliding with the same feel as the follow-scroll.
                .offset(
                    x: 12 + (cursorPoint?.x ?? 0),
                    y: max(0, 8 + (cursorPoint?.y ?? CGFloat(focusLine) * lineHeight) - 17)
                )
                .animation(allowsHighlighting && !reduceMotion ? .snappy(duration: 0.2) : nil, value: focusLine)
        }
    }

    /// Scrolls so `line` sits about a third of the way down the viewport - in view
    /// with the context around it, without pinning the action to an edge (#983).
    /// The offset is estimated from the monospaced line height: the content is one
    /// `Text`, so there's no per-line view identity to scroll to.
    private func scroll(toLine line: Int?, animated: Bool) {
        guard let line else { return }

        let target = max(0, CGFloat(line) * lineHeight + 8 - embeddedViewportHeight / 3)
        if animated {
            withAnimation(.snappy(duration: 0.2)) {
                scrollPosition.scrollTo(y: target)
            }
        } else {
            scrollPosition.scrollTo(y: target)
        }
    }

    // The height of one rendered line of monospaced source.
    #if os(macOS)
        func platformCodeFont(scale: CGFloat = 1) -> NSFont {
            let size = NSFont.preferredFont(forTextStyle: .callout).pointSize * scale
            return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        }
    #else
        func platformCodeFont(scale: CGFloat = 1) -> UIFont {
            #if os(visionOS)
                let size = UIFont.preferredFont(forTextStyle: .body).pointSize * scale
            #else
                let size = UIFont.preferredFont(forTextStyle: .callout).pointSize * scale
            #endif
            return UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
        }
    #endif

    var codeFont: Font {
        Font(platformCodeFont(scale: fontScale))
    }

    /// The height of one rendered line of source.
    var lineHeight: CGFloat {
        #if os(macOS)
            let font = platformCodeFont(scale: fontScale)
            return ceil(font.ascender - font.descender + font.leading)
        #else
            ceil(platformCodeFont(scale: fontScale).lineHeight)
        #endif
    }

    /// A determinate nested-scroll height that hugs short snippets and caps long
    /// files, retaining the no-feedback-loop guarantee from #494.
    func embeddedHeight(for contents: String, maxHeight: CGFloat = 360) -> CGFloat {
        let lines = max(1, contents.split(separator: "\n", omittingEmptySubsequences: false).count)
        return min(maxHeight, max(72, CGFloat(lines) * lineHeight + 24))
    }

    /// The copy button overlaid on the code block. Liquid Glass keeps it distinct
    /// from syntax colours beneath it, and it confirms with a brief checkmark.
    private var copyButton: some View {
        Button {
            copy()
        } label: {
            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                .padding(5)
        }
        .controlSize(.small)
        .glassActionButtonStyle()
        .touchTarget() // 44pt touch floor on iPad, no-op on macOS (#597)
        .pointerHoverEffect() // pointer hover highlight on iPad (#586)
        .help("Copy code")
        .accessibilityLabel("Copy code")
        // Reveal on hover on macOS. While transparent it must also leave hit
        // testing, keyboard focus, and the accessibility tree; opacity alone
        // otherwise exposes a phantom Copy button (#1913). On iPad it stays shown.
        #if os(macOS)
            .opacity(isHovering ? 1 : 0)
            .allowsHitTesting(isHovering)
            .focusable(isHovering)
            .accessibilityHidden(!isHovering)
            .animation(.easeInOut(duration: 0.12), value: isHovering)
        #endif
    }

    /// Copies the file's contents to the clipboard. A syntax-highlighted RTF
    /// representation rides along so pasting into Pages, Mail, or a doc keeps the
    /// colours; plain text stays the fallback for editors and the terminal. The
    /// RTF is produced off the main actor (#372), so the write happens once ready.
    private func copy() {
        copyGeneration += 1
        let generation = copyGeneration
        // Plain text lands synchronously, so the newest copy - from this or any other
        // view - always wins the clipboard, and the checkmark is honest (#750).
        Clipboard.copy(contents)
        let baseline = Self.pasteboardChangeCount
        didCopy = true
        scheduleCopyReset(for: generation)
        copyTask?.cancel()
        copyTask = Task {
            let rtf = await SyntaxHighlighter.rtf(contents, language: language, dark: dark)
            // Add the rich-text flavor only while our plain-text write is still the
            // latest pasteboard change: the clipboard is global, so a newer copy from
            // any other view (another file, a URL from a context menu) must never be
            // replaced by this older content finishing late (#750).
            guard !Task.isCancelled, copyGeneration == generation,
                  Self.pasteboardChangeCount == baseline else { return }

            BuddyAppKit.Clipboard.copy(contents, rtf: rtf)
        }
    }

    /// The system pasteboard's change counter, bumped by every write from any app.
    private static var pasteboardChangeCount: Int {
        #if os(macOS)
            NSPasteboard.general.changeCount
        #else
            UIPasteboard.general.changeCount
        #endif
    }

    private func scheduleCopyReset(for generation: Int) {
        copyResetTask?.cancel()
        copyResetTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled, copyGeneration == generation else { return }

            didCopy = false
        }
    }
}

/// The inputs that determine a highlight pass, so `HighlightedCode`'s `.task`
/// restarts exactly when one of them changes.
private struct HighlightInput: Equatable {
    let contents: String
    let language: String?
    let dark: Bool
    let allowsHighlighting: Bool
}

private struct ScrollTarget: Equatable {
    let line: Int?
    let cursorOffset: Int?
    let identity: String?
}
