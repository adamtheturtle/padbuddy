//
//  InlineEditableTitle.swift
//  coderpad
//
//  A heading that doubles as an editable text field. It reads as a plain title
//  until hovered or focused, when a subtle pencil fades in to signal that it can be
//  edited in place. Shared by the pad and question detail headers so the affordance
//  stays identical in both.
//

import SwiftUI

struct InlineEditableTitle: View {
    @Binding var text: String
    var placeholder: LocalizedStringKey
    /// The owning view keeps the focus state so it can drive the field from a menu
    /// command and commit the edit when focus leaves.
    var focus: FocusState<Bool>.Binding
    var onCommit: () -> Void

    @State private var hovered = false
    /// While offline the app is read-only, so the title isn't editable (#321).
    @Environment(\.isReadOnly) private var isReadOnly

    /// The title's natural (untruncated) width, and the row's available width.
    /// Together they cap the editable field so it hugs a short title (keeping the
    /// pencil tucked beside it) yet truncates a long one instead of forcing the
    /// detail pane wider — which would inflate the split view's ideal width and
    /// shove the columns around when you select a wide-titled pad (#429).
    @State private var naturalWidth: CGFloat = 0
    @State private var availableWidth: CGFloat = 0

    /// Room reserved at the trailing edge for the pencil hint plus its spacing, so a
    /// truncated title doesn't run right up against (or under) the pencil.
    private static let pencilReserve: CGFloat = 28

    /// The pencil is a hint, not a control. Hidden while read-only, where the title
    /// can't be edited at all. On macOS it appears only while the row is hovered or
    /// the field is focused, keeping the header clean otherwise. iPad has no hover, so
    /// a hover-gated pencil would never show and the title reads as non-editable —
    /// there it's shown persistently, matching the other inline editors' touch
    /// affordances (the favorite star, the field pencils).
    private var showsPencil: Bool {
        guard !isReadOnly else { return false }
        #if os(macOS)
            return hovered || focus.wrappedValue
        #else
            return true
        #endif
    }

    /// Width to pin the field to: the title's natural width, clamped to what the
    /// row can show. `nil` until both measurements arrive (and for an empty title),
    /// leaving the field flexible so the placeholder still shows.
    private var fieldWidth: CGFloat? {
        guard naturalWidth > 0, availableWidth > 0 else { return nil }

        return min(naturalWidth, max(0, availableWidth - Self.pencilReserve))
    }

    var body: some View {
        HStack(spacing: 6) {
            TextField(placeholder, text: $text)
                .font(.title.bold())
                .textFieldStyle(.plain)
                .focused(focus)
                .onSubmit(onCommit)
                .disabled(isReadOnly)
                .lineLimit(1)
                // Hug the title up to the available width; a longer title is capped
                // here and truncates rather than widening the whole pane (#429).
                .frame(width: fieldWidth, alignment: .leading)
                // A plain TextField hard-*clips* an over-long title instead of showing
                // a trailing ellipsis (#445). While not editing, hide the field's text
                // and overlay a tail-truncating Text in its place so a long title reads
                // "Some long titl…". The overlay carries an explicit tap-to-focus
                // rather than relying on the click "falling through" to the invisible
                // field — an opacity-0 TextField doesn't reliably become first
                // responder on click, which left the title looking uneditable (#461).
                .opacity(focus.wrappedValue ? 1 : 0)
                .overlay(alignment: .leading) {
                    if !focus.wrappedValue {
                        truncatingDisplay
                            .contentShape(Rectangle())
                            .onTapGesture { if !isReadOnly { focus.wrappedValue = true } }
                            .accessibilityAddTraits(.isButton)
                    }
                }
                .background(titleWidthReader)
                .accessibilityHint("Edit title")
            Image(systemName: "pencil")
                .font(.callout)
                .foregroundStyle(.secondary)
                .opacity(showsPencil ? 1 : 0)
                // The ~17pt pencil is shown persistently on iPad, so give it a 44pt hit
                // area on touch (no-op on macOS, #597). Applied before the tap gesture so
                // the enlarged frame is what registers the tap.
                .touchTarget()
                // Highlight the pencil under the iPad pointer (#586).
                .pointerHoverEffect()
                // The pencil is a hint, but clicking it should begin editing too, not
                // just hovering the title (#472). Tap-to-focus mirrors the resting
                // title overlay above.
                .contentShape(Rectangle())
                .onTapGesture { if !isReadOnly { focus.wrappedValue = true } }
                .accessibilityHidden(true)
                .accessibilityAddTraits(.isButton)
            // Keeps the field + pencil pinned to the leading edge and makes the HStack
            // always fill the row, so the width reader below measures the pane's true
            // width rather than the hugged content — otherwise the cap would feed back
            // on itself.
            Spacer(minLength: 0)
        }
        // `onGeometryChange` coalesces the width write into a single update per
        // frame; the older GeometryReader-in-background + onAppear + onChange combo
        // wrote `availableWidth` twice in a frame, re-laying out the title text and
        // tripping SwiftUI's "onChange(of: AnyTextLayoutCollection) … multiple times
        // per frame" fault.
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: showsPencil)
    }

    /// The resting (non-editing) title: a tail-truncating `Text` shown over the
    /// hidden field so a long title ends in an ellipsis instead of being clipped
    /// (#445). The overlaying view owns a tap-to-focus gesture (#461); this is
    /// hidden from accessibility since the field already exposes the title. A tooltip
    /// surfaces the full title when it's truncated.
    private var truncatingDisplay: some View {
        Group {
            if text.isEmpty {
                Text(placeholder).foregroundStyle(.secondary)
            } else {
                Text(text).help(text)
            }
        }
        .font(.title.bold())
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }

    /// Measures the title's natural width from a hidden, `fixedSize` copy of the
    /// text so the reported value is the untruncated width even while the visible
    /// field is clamped and line-limited.
    private var titleWidthReader: some View {
        Text(text)
            .font(.title.bold())
            .lineLimit(1)
            .fixedSize()
            .hidden()
            // Coalesced single-update geometry read, matching the available-width
            // reader above and avoiding the per-frame text-relayout fault.
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { naturalWidth = $0 }
    }
}

private struct InlineEditableTitlePreview: View {
    // Preview-only @State read via its $-projected binding.
    // periphery:ignore
    @State private var short = "Short Pad"
    // Preview-only @State read via its $-projected binding.
    // periphery:ignore
    @State private var long = "An Extremely Long Pad Title That Would Otherwise Re-Jig The Whole Window"
    @FocusState private var focus: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            InlineEditableTitle(text: $short, placeholder: "Untitled Pad", focus: $focus) {}
                .border(.red)
            InlineEditableTitle(text: $long, placeholder: "Untitled Pad", focus: $focus) {}
                .border(.red)
        }
        // A narrow pane: the long title must truncate within this width rather than
        // forcing the row (red border) wider.
        .frame(width: 320, alignment: .leading)
        .padding()
    }
}

#Preview {
    InlineEditableTitlePreview()
}
