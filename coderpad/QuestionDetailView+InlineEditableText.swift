//
//  QuestionDetailView+InlineEditableText.swift
//  coderpad
//

import SwiftUI

/// In-progress inline edits that outlive their editor's view. Question detail's
/// Prompt/Materials/Solution panes are mutually exclusive `switch` branches, so a
/// tab switch unmounts the pane and destroys the editor's `@State` draft; without
/// this stash a routine hop between tabs silently discarded unsaved text (#1020).
/// Session-scoped only - drafts are never persisted.
@MainActor
final class InlineEditDrafts {
    static let shared = InlineEditDrafts()

    private var drafts: [String: String] = [:]

    func stash(_ draft: String, for key: String) {
        drafts[key] = draft
    }

    /// Removes and returns the stashed draft for `key`, so a draft is resumed at
    /// most once.
    func take(for key: String) -> String? {
        drafts.removeValue(forKey: key)
    }
}

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
    /// Stable identity of this field across mounts (question/pad id + field), so an
    /// in-progress edit survives its pane being unmounted by a tab switch (#1020).
    let draftKey: String
    /// Commits the edited text, returning `true` on success so the editor closes.
    let onSave: (String) async -> Bool

    /// While offline the app is read-only, so long-form fields aren't editable (#321).
    @Environment(\.isReadOnly) private var isReadOnly
    /// Drop the hover fade when Reduce Motion is on (#614).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editing = false
    @State private var draft = ""
    @State private var baseText = ""
    @State private var sourceChanged = false
    @State private var saving = false
    @State private var hovered = false
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if editing { editor } else { display }
        }
        .onHover { hovered = $0 }
        .onChange(of: text) { _, newValue in
            handleSourceChange(newValue)
        }
        .onAppear { resumeStashedDraft() }
        // Unmounted mid-edit (e.g. the hosting tab switched away): stash the dirty
        // draft so coming back resumes the edit instead of losing it (#1020).
        .onDisappear {
            if editing, draft != text {
                InlineEditDrafts.shared.stash(draft, for: draftKey)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.12), value: hovered)
    }

    /// Reopens the editor with a draft stashed when this field was last unmounted
    /// mid-edit. A stash matching the current source is dropped instead: the edit
    /// either got saved after the unmount or no longer changes anything.
    private func resumeStashedDraft() {
        guard !isReadOnly, let stored = InlineEditDrafts.shared.take(for: draftKey),
              stored != text else { return }

        draft = stored
        baseText = text
        sourceChanged = false
        editing = true
        focused = true
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
            if sourceChanged {
                HStack(spacing: 8) {
                    Label("Changed elsewhere", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                    Spacer(minLength: 0)
                    Button("Use Latest") {
                        useLatestSource()
                    }
                }
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Cancel") { cancel() }
                    .disabled(saving)
                Button { Task { await commit() } } label: {
                    if saving {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(sourceChanged ? "Save Anyway" : "Save")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(saving)
            }
        }
    }

    private func beginEditing() {
        draft = text
        baseText = text
        sourceChanged = false
        editing = true
        focused = true
    }

    private func cancel() {
        editing = false
        focused = false
        sourceChanged = false
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
            sourceChanged = false
        }
    }

    private func handleSourceChange(_ newValue: String) {
        guard editing, newValue != baseText else { return }

        if draft == baseText {
            draft = newValue
            baseText = newValue
            sourceChanged = false
        } else {
            baseText = newValue
            sourceChanged = true
        }
    }

    private func useLatestSource() {
        draft = text
        baseText = text
        sourceChanged = false
    }
}
