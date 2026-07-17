//
//  CommandEditableTitle.swift
//  coderpad
//

import SwiftUI

/// Inline title editor that can also be opened by a menu command. `InlineEditableTitle`
/// owns its edit state privately, so the Pad menu needs this app-side variant to make
/// Pad > Edit Pad enter the same rename affordance a click would.
struct CommandEditableTitle: View {
    let title: String
    var placeholder: LocalizedStringKey = "Name"
    var isEditable = true
    var clampsWidth = false
    var font: Font = .title2.weight(.semibold)
    var editRequest: Int
    let onCommit: (String) async -> Bool

    @Environment(\.isReadOnly) private var isReadOnly
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isEditing = false
    @State private var draft = ""
    @State private var editingBaseTitle = ""
    @State private var titleConflict = false
    @State private var isHovering = false
    @State private var isSaving = false
    @State private var naturalWidth: CGFloat = 0
    @State private var availableWidth: CGFloat = 0
    @FocusState private var fieldFocused: Bool

    private static let pencilReserve: CGFloat = 28

    private var editingAllowed: Bool {
        isEditable && !isReadOnly
    }

    private var showsPencil: Bool {
        guard editingAllowed else { return false }

        #if os(macOS)
            return isHovering
        #else
            return true
        #endif
    }

    private var fieldWidth: CGFloat? {
        guard clampsWidth, naturalWidth > 0, availableWidth > 0 else { return nil }

        return min(naturalWidth, max(0, availableWidth - Self.pencilReserve))
    }

    var body: some View {
        Group {
            if isEditing {
                editorField
            } else if editingAllowed {
                editableTitle
            } else {
                plainTitle
            }
        }
        .font(font)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: editRequest) { _, _ in beginEditing() }
        .onChange(of: title) { _, newTitle in sourceTitleChanged(to: newTitle) }
    }

    private var plainTitle: some View {
        Text(title)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var editableTitle: some View {
        HStack(spacing: 6) {
            Text(title)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(clampsWidth ? 1 : nil)
                .truncationMode(.tail)
                .frame(maxWidth: fieldWidth, alignment: .leading)
                .background {
                    if clampsWidth { titleWidthReader }
                }

            Image(systemName: "pencil")
                .font(.callout)
                .foregroundStyle(.secondary)
                .opacity(showsPencil ? 1 : 0)
                .touchTarget()
                .pointerHoverEffect()
                .accessibilityHidden(true)

            Spacer(minLength: 0)
        }
        .contentShape(.rect)
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.12), value: showsPencil)
        .onTapGesture { beginEditing() }
        .help("Rename")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Edit title")
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
    }

    private var editorField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField(placeholder, text: $draft)
                    .textFieldStyle(.plain)
                    .focused($fieldFocused)
                    .disabled(isSaving)
                    .lineLimit(1)
                    .frame(maxWidth: fieldWidth, alignment: .leading)
                    .onSubmit { Task { await commit() } }
                    .onChange(of: fieldFocused) { _, focused in
                        if !focused, isEditing { Task { await commit() } }
                    }

                if isSaving {
                    ProgressView().controlSize(.small)
                }
            }

            if titleConflict {
                HStack(spacing: 8) {
                    Text("Title changed elsewhere.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Use Latest") { useLatestTitle() }
                    Button("Save Anyway") {
                        titleConflict = false
                        editingBaseTitle = title
                        Task { await commit() }
                    }
                }
                .font(.caption)
            }
        }
    }

    private var titleWidthReader: some View {
        Text(title)
            .font(font)
            .lineLimit(1)
            .fixedSize()
            .hidden()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { naturalWidth = $0 }
    }

    private func beginEditing() {
        guard editingAllowed else { return }

        draft = title
        editingBaseTitle = title
        titleConflict = false
        isEditing = true
        fieldFocused = true
    }

    private func commit() async {
        guard isEditing, !isSaving else { return }
        guard !titleConflict else {
            fieldFocused = true
            return
        }
        guard let value = InlineEdit.commitValue(original: editingBaseTitle, edited: draft) else {
            isEditing = false
            return
        }

        isSaving = true
        let saved = await onCommit(value)
        isSaving = false
        if saved {
            isEditing = false
            fieldFocused = false
        } else {
            fieldFocused = true
        }
    }

    private func sourceTitleChanged(to newTitle: String) {
        guard isEditing, newTitle != editingBaseTitle else { return }

        if draft == editingBaseTitle || draft == newTitle {
            draft = newTitle
            editingBaseTitle = newTitle
            titleConflict = false
        } else {
            titleConflict = true
        }
    }

    private func useLatestTitle() {
        draft = title
        editingBaseTitle = title
        titleConflict = false
        fieldFocused = true
    }
}
