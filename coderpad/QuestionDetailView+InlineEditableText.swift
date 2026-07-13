//
//  QuestionDetailView+InlineEditableText.swift
//  coderpad
//

import SwiftUI

/// A long-form field that reads as rendered Markdown until you click its hover
/// pencil, when it becomes a text editor with Save / Cancel. Each commit sends a
/// single-field `PUT` for the question (see `QuestionDetailView` commits), so the
/// description, each candidate-instruction part, and the solution are all edited in
/// place rather than in a separate window (#335). Empty fields still render (showing
/// `placeholder`) so they can be filled in (#333).
struct InlineEditableText: View {
    let text: String
    var placeholder: LocalizedStringKey
    /// Human-readable name of this field, used for the pencil's help/accessibility
    /// label (e.g. "description", "part 2").
    var label: String
    /// Commits the edited text, returning `true` on success so the editor closes.
    let onSave: (String) async -> Bool

    /// While offline the app is read-only, so long-form fields aren't editable (#321).
    @Environment(\.isReadOnly) private var isReadOnly
    /// Drop the hover fade when Reduce Motion is on (#614).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editing = false
    @State private var draft = ""
    @State private var saving = false
    @State private var hovered = false
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if editing { editor } else { display }
        }
        .onHover { hovered = $0 }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.12), value: hovered)
    }

    private var display: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Group {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                } else {
                    // Textual's selectable-markdown overlay observes SwiftUI text
                    // layout internally. In this inline editor shell the hover/edit
                    // controls can rebuild the block tree repeatedly in one frame,
                    // which trips SwiftUICore's layout-collection fault.
                    MarkdownText(text)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .environment(\.isRasterizedForPrint, true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !isReadOnly {
                Button { beginEditing() } label: {
                    Image(systemName: "pencil")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                // No hover on touch: keep the inline-edit affordance visible on iPad.
                #if os(macOS)
                    .opacity(hovered ? 1 : 0)
                #else
                    .opacity(1)
                #endif
                    .help("Edit \(label)")
                    .accessibilityLabel("Edit \(label)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $draft)
                .font(.callout)
                .frame(minHeight: 90)
                .focused($focused)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color.platformTextBackground,
                            in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .stroke(Color.subtleStroke, lineWidth: 1))
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Cancel") { cancel() }
                    .disabled(saving)
                Button { Task { await commit() } } label: {
                    if saving { ProgressView().controlSize(.small) } else { Text("Save") }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(saving)
            }
        }
    }

    private func beginEditing() {
        draft = text
        editing = true
        focused = true
    }

    private func cancel() {
        editing = false
        focused = false
    }

    private func commit() async {
        saving = true
        let saved = await onSave(draft)
        saving = false
        // On failure the detail view surfaces the error in its alert; keep the
        // editor open so the unsaved text isn't lost.
        if saved {
            editing = false
            focused = false
        }
    }
}
