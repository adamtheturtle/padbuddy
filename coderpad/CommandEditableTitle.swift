//
//  CommandEditableTitle.swift
//  coderpad
//

import SwiftUI

struct CommandTitleEditScope: Equatable {
    let accountID: UUID?
    let itemID: String
    let title: String
}

struct CommandTitleEditRequest: Equatable {
    let nonce: UUID
    let scope: CommandTitleEditScope

    init(scope: CommandTitleEditScope, nonce: UUID = UUID()) {
        self.nonce = nonce
        self.scope = scope
    }

    func matches(_ currentScope: CommandTitleEditScope, editingAllowed: Bool) -> Bool {
        editingAllowed && scope == currentScope
    }
}

enum CommandTitleEditFocusPolicy {
    /// Focus can move for alerts, accessibility navigation, window activation,
    /// or another control. None of those is consent to rename (#1432).
    static func shouldCommit(focused _: Bool) -> Bool {
        false
    }
}

/// Inline title editor that can also be opened by a menu command. `InlineEditableTitle`
/// owns its edit state privately, so the Pad menu needs this app-side variant to make
/// Pad > Edit Pad enter the same rename affordance a click would.
struct CommandEditableTitle: View {
    let title: String
    var placeholder: LocalizedStringKey = "Name"
    var isEditable = true
    var clampsWidth = false
    var font: Font = .title2.weight(.semibold)
    let scope: CommandTitleEditScope
    var editRequest: CommandTitleEditRequest?
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
    /// The in-flight commit, held so it can be cancelled when this editor goes
    /// away — see the `onDisappear` in `body` (#2018).
    @State private var saveTask: Task<Void, Never>?
    @FocusState private var fieldFocused: Bool

    private static let pencilReserve: CGFloat = 28
    /// Hidden text exists only to estimate the field width. Measuring an entire
    /// untrusted remote title makes CoreText work proportional to an otherwise
    /// unbounded payload even though the result is clamped to the container.
    private static let maximumMeasuredTitleLength = 512
    /// Floor for the width clamp. In a narrow layout the pencil reserve can consume
    /// the whole available width, which rendered the editing field at zero width
    /// with nothing to type into (#2020). This is a maximum, so a title narrower
    /// than the floor still lays out at its natural size.
    private static let minimumClampedWidth: CGFloat = 80

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

        return max(Self.minimumClampedWidth, min(naturalWidth, availableWidth - Self.pencilReserve))
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
        .onChange(of: editRequest) { _, request in
            guard request?.matches(scope, editingAllowed: editingAllowed) == true else { return }

            beginEditing()
        }
        .onChange(of: title) { _, newTitle in sourceTitleChanged(to: newTitle) }
        // Submit and focus loss start the save off-view, so navigating away left it
        // running: the request could still land and rename a pad the detail view is
        // no longer showing (#2018).
        .onDisappear {
            saveTask?.cancel()
            saveTask = nil
        }
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
        // The tap gesture is pointer-only, so the button trait promised an
        // activation that VoiceOver and Full Keyboard Access had no way to perform
        // (#2019). The explicit default action is what they invoke.
        .accessibilityAction { beginEditing() }
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
                    .onSubmit { startCommit() }
                    .onChange(of: fieldFocused) { _, focused in
                        if CommandTitleEditFocusPolicy.shouldCommit(focused: focused), isEditing {
                            startCommit()
                        }
                    }

                if isSaving {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Save") { startCommit() }
                        .disabled(titleConflict)
                    Button("Cancel", role: .cancel) { cancelEditing() }
                }
            }

            if titleConflict {
                HStack(spacing: 8) {
                    Text("Title changed elsewhere.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Use Latest") { useLatestTitle() }
                }
                .font(.caption)
            }
        }
    }

    private var titleWidthReader: some View {
        Text(String(title.prefix(Self.maximumMeasuredTitleLength)))
            .font(font)
            .lineLimit(1)
            .fixedSize()
            .hidden()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { naturalWidth = $0 }
    }

    private func beginEditing() {
        guard editingAllowed else { return }

        // A menu command can fire while an editor is already open, including while
        // its save is still in flight. Resetting the draft there let the older
        // commit's completion close the editor over the newer input and discard it
        // (#2017), so an edit request for a live session only re-focuses the field.
        guard !isEditing, !isSaving else {
            fieldFocused = true
            return
        }

        draft = title
        editingBaseTitle = title
        titleConflict = false
        isEditing = true
        fieldFocused = true
    }

    private func cancelEditing() {
        guard !isSaving else { return }

        draft = title
        editingBaseTitle = title
        titleConflict = false
        isEditing = false
        fieldFocused = false
    }

    /// Runs a commit as the tracked save, so `onDisappear` can cancel it (#2018).
    private func startCommit() {
        guard isEditing, !isSaving else { return }
        guard !titleConflict else {
            fieldFocused = true
            return
        }
        guard let value = InlineEdit.commitValue(original: editingBaseTitle, edited: draft) else {
            isEditing = false
            return
        }

        // Claim the commit synchronously before spawning. Focus loss can fire in
        // the same event turn as Save Anyway; setting this inside the Task left a
        // window where both paths launched a PUT (#1433).
        isSaving = true
        saveTask = Task { await commit(value) }
    }

    private func commit(_ value: String) async {
        let saved = await onCommit(value)
        // The spinner flag is cleared either way: it belongs to state SwiftUI reuses
        // for whatever this position shows next.
        isSaving = false
        // Cancelled by the view going away (#2018): this editor no longer belongs to
        // the title that was being saved, so none of the transitions below apply.
        guard !Task.isCancelled else { return }

        if saved {
            isEditing = false
            fieldFocused = false
            AccessibilityNotification.Announcement(String(localized: "Title saved")).post()
        } else {
            fieldFocused = true
        }
    }

    private func sourceTitleChanged(to newTitle: String) {
        guard isEditing, newTitle != editingBaseTitle else { return }

        // Only an untouched draft follows the source silently. A remote title that
        // happens to match what was typed here is still someone else's edit, and
        // adopting it as the new base hid that from the user and let the next save
        // report success over an unreviewed change (#2021).
        if draft == editingBaseTitle {
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
