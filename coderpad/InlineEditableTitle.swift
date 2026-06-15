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
    var placeholder: String
    /// The owning view keeps the focus state so it can drive the field from a menu
    /// command and commit the edit when focus leaves.
    var focus: FocusState<Bool>.Binding
    var onCommit: () -> Void

    @State private var hovered = false

    /// The pencil is a hint, not a control, so it appears only while the row is
    /// hovered or the field is focused — keeping the header clean otherwise.
    private var showsPencil: Bool { hovered || focus.wrappedValue }

    var body: some View {
        HStack(spacing: 6) {
            // `fixedSize` keeps the pencil tucked next to the text rather than at the
            // far edge of the pane, so it reads as "edit this title".
            TextField(placeholder, text: $text)
                .font(.title.bold())
                .textFieldStyle(.plain)
                .focused(focus)
                .onSubmit(onCommit)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityHint("Edit title")
            Image(systemName: "pencil")
                .font(.callout)
                .foregroundStyle(.secondary)
                .opacity(showsPencil ? 1 : 0)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: showsPencil)
    }
}
