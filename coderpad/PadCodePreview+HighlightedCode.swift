//
//  PadCodePreview+HighlightedCode.swift
//  coderpad
//
//  The scrollable, syntax-highlighted single-file view used by the code cards
//  (see `EnvironmentCodeCard`). Split out of `PadCodePreview.swift` to keep each
//  file under the length limit.
//

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
struct HighlightedCode: View, Equatable {
    let contents: String
    let language: String?
    let dark: Bool
    /// When true the scroll fills whatever height it's given instead of pinning to
    /// 360. Only safe when this is the *outermost* vertical scroll (the full-screen
    /// viewer) — inside the detail pane's own vertical scroll the fixed height is
    /// what avoids the combinatorial re-measure hang (#494), so the card keeps it.
    var fillsHeight = false

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

    /// Briefly flips the copy button to a checkmark after a successful copy, so a
    /// click gives visible confirmation. Reset after a short delay.
    @State private var didCopy = false
    @State private var copyGeneration = 0
    @State private var copyTask: Task<Void, Never>?
    @State private var copyResetTask: Task<Void, Never>?

    /// Compare only the inputs (not the @State result) so SwiftUI keeps skipping
    /// re-renders for unrelated reasons, e.g. the file sidebar's resize drag.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.contents == rhs.contents && lhs.language == rhs.language
            && lhs.dark == rhs.dark && lhs.fillsHeight == rhs.fillsHeight
    }

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            Text(displayText)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .defaultScrollAnchor(.topLeading)
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
        .frame(height: fillsHeight ? nil : 360)
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
        // Re-run only when the inputs change; a same-id task isn't restarted, so
        // an unrelated re-render won't re-highlight.
        .task(id: HighlightInput(contents: contents, language: language, dark: dark)) {
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
        if let highlighted, highlightedContents == contents { return highlighted }
        return AttributedString(contents)
    }

    /// The copy button overlaid on the code block. Backed by a material so it
    /// stays legible over any syntax colours, and confirms with a brief checkmark.
    private var copyButton: some View {
        Button {
            copy()
        } label: {
            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                .padding(5)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .touchTarget() // 44pt touch floor on iPad, no-op on macOS (#597)
        .pointerHoverEffect() // pointer hover highlight on iPad (#586)
        .help("Copy code")
        .accessibilityLabel("Copy code")
        // Reveal on hover on macOS; opacity (not `hidden`) keeps it clickable and
        // in the accessibility tree. On iPad it's always shown.
        #if os(macOS)
            .opacity(isHovering ? 1 : 0)
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

            Clipboard.copy(contents, rtf: rtf)
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
}
