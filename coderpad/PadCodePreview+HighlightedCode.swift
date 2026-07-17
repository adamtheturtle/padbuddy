//
//  PadCodePreview+HighlightedCode.swift
//  coderpad
//
//  The scrollable, syntax-highlighted single-file view used by the code cards
//  (see `EnvironmentCodeCard`). Split out of `PadCodePreview.swift` to keep each
//  file under the length limit.
//

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
            Text(highlighted ?? AttributedString(contents))
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
        // Re-run only when the inputs change; a same-id task isn't restarted, so
        // an unrelated re-render won't re-highlight.
        .task(id: HighlightInput(contents: contents, language: language, dark: dark)) {
            highlighted = await SyntaxHighlighter.highlight(contents, language: language, dark: dark)
        }
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
        didCopy = false
        copyTask?.cancel()
        copyTask = Task {
            let rtf = await SyntaxHighlighter.rtf(contents, language: language, dark: dark)
            guard !Task.isCancelled, copyGeneration == generation else { return }

            Clipboard.copy(contents, rtf: rtf)
            didCopy = true
            scheduleCopyReset(for: generation)
        }
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
