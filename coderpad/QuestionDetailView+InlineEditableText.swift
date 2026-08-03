//
//  QuestionDetailView+InlineEditableText.swift
//  coderpad
//

import SwiftUI

/// In-progress inline edits that outlive their editor's view. Question detail's
/// Description/Instructions/Materials/Solution panes are mutually exclusive `switch` branches, so a
/// tab switch unmounts the pane and destroys the editor's `@State` draft; without
/// this stash a routine hop between tabs silently discarded unsaved text (#1020).
/// Session-scoped only - drafts are never persisted.
@MainActor
final class InlineEditDrafts {
    static let shared = InlineEditDrafts()

    /// At most this many stashes are retained; the least recently stashed is
    /// evicted first. Unbounded growth would retain arbitrarily many private
    /// prompts/solutions for the life of the process (#1195).
    private let capacity = 32

    private var drafts: [String: String] = [:]
    /// Stash order, oldest first, for capacity eviction.
    private var order: [String] = []

    func stash(_ draft: String, for key: String) {
        order.removeAll { $0 == key }
        order.append(key)
        drafts[key] = draft
        while order.count > capacity, let oldest = order.first {
            order.removeFirst()
            drafts.removeValue(forKey: oldest)
        }
    }

    /// Removes and returns the stashed draft for `key`, so a draft is resumed at
    /// most once.
    func take(for key: String) -> String? {
        order.removeAll { $0 == key }
        return drafts.removeValue(forKey: key)
    }

    /// Drops the stash for `key` without resuming it — a save that succeeded after
    /// its editor unmounted must not reopen stale editing over the saved source (#1193).
    func clear(for key: String) {
        order.removeAll { $0 == key }
        drafts.removeValue(forKey: key)
    }

    /// A short, session-stable token of a field's mount-time content, for keys
    /// whose fields have no server identity (candidate-instruction parts): a
    /// stash bound to the text it was opened over can never be restored into a
    /// different part after a reorder (#1798). Session-scoped like the stash
    /// itself, so per-launch hash randomization is fine.
    nonisolated static func contentToken(_ text: String) -> String {
        String(text.hashValue, radix: 36, uppercase: false)
    }

    /// Drops every stash belonging to `account`, so a removed account's unsaved
    /// private content doesn't outlive it and can't be restored into another
    /// organization's fields (#1194). Keys embed the owning account's UUID (see
    /// `QuestionDetailView.inlineDraftKey` and the pad notes key).
    func removeAll(account: UUID) {
        let marker = "/\(account.uuidString)/"
        for key in drafts.keys where key.contains(marker) {
            clear(for: key)
        }
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
    /// Qualified by the window before use — see `stashKey`.
    let draftKey: String
    /// Commits the edited text, returning `true` on success so the editor closes.
    ///
    /// `basedOn` is the source value this editor is currently showing — what the
    /// user believes they are replacing. The commit checks the server still holds
    /// it before overwriting, so an edit made elsewhere that never reached this
    /// client is surfaced as a conflict rather than silently clobbered (#2647).
    let onSave: (_ text: String, _ basedOn: String) async -> Bool

    /// While offline the app is read-only, so long-form fields aren't editable (#321).
    @Environment(\.isReadOnly) private var isReadOnly
    /// Drop the hover fade when Reduce Motion is on (#614).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Which window this editor is in, so two windows editing the same field keep
    /// separate drafts — see `stashKey`.
    @Environment(\.windowScope) private var windowScope
    @State private var editing = false
    @State private var draft = ""
    @State private var baseText = ""
    @State private var sourceChanged = false
    @State private var saving = false
    @State private var hovered = false
    @State private var showingDiscardConfirmation = false
    @State private var showsPlainText = false
    @FocusState private var focused: Bool

    /// The key this editor stashes under: the field's identity plus the window's.
    ///
    /// The stash holds one draft per key, so keying on the field alone meant two
    /// windows open on the same pad or question shared a slot — whichever editor
    /// unmounted last replaced the other window's unsaved text, and the other
    /// window then resumed the wrong draft (#2645). Qualifying by window keeps
    /// them apart while preserving what the stash is for: a tab switch happens
    /// inside one window, so that window's own draft still comes back (#1020).
    private var stashKey: String {
        "\(draftKey)@\(windowScope.token)"
    }

    var body: some View {
        Group {
            if editing {
                editor
            } else {
                display
            }
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
                InlineEditDrafts.shared.stash(draft, for: stashKey)
            }
        }
        .confirmationDialog(
            "Discard unsaved changes to \(label)?",
            isPresented: $showingDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard Changes", role: .destructive) { discardDraft() }
            Button("Keep Editing", role: .cancel) {}
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.12), value: hovered)
    }

    /// Reopens the editor with a draft stashed when this field was last unmounted
    /// mid-edit. A stash matching the current source is dropped instead: the edit
    /// either got saved after the unmount or no longer changes anything.
    private func resumeStashedDraft() {
        guard !isReadOnly, let stored = InlineEditDrafts.shared.take(for: stashKey),
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
                } else if showsPlainText {
                    Text(text)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
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
            Button {
                showsPlainText.toggle()
            } label: {
                Image(systemName: showsPlainText ? "text.badge.checkmark" : "text.quote")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(showsPlainText ? "Show formatted text" : "Show plain text")
            .accessibilityLabel(showsPlainText ? "Show formatted text" : "Show plain text")
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
                // Let the user inspect what changed remotely before choosing "Save
                // Anyway" (which overwrites it) or "Use Latest" (which discards the
                // draft), so a manual merge is possible instead of a blind pick (#1196).
                DisclosureGroup("Latest version") {
                    MarkdownText(baseText.isEmpty ? String(localized: "Empty") : baseText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .environment(\.isRasterizedForPrint, true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
                .font(.callout)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Cancel") { requestCancel() }
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

    private func requestCancel() {
        guard draft != text else {
            discardDraft()
            return
        }

        showingDiscardConfirmation = true
    }

    private func discardDraft() {
        // An explicit cancel abandons the edit everywhere: a stash left by an
        // earlier unmount (e.g. one skipped by the read-only resume guard) must
        // not reopen the abandoned edit on a later mount (#1806).
        InlineEditDrafts.shared.clear(for: stashKey)
        editing = false
        focused = false
        sourceChanged = false
    }

    private func commit() async {
        // Which field this save belongs to. SwiftUI reuses a view's `@State` when
        // it rebinds the same view position to different content, so by the time
        // the request returns this editor may be showing another part, another
        // question, or nothing at all (#2653).
        let committedKey = stashKey
        saving = true
        let saved = await onSave(draft, text)
        // The spinner flag is cleared either way: it belongs to the reused state,
        // and leaving it set would strand the next field's editor mid-save.
        saving = false
        guard !Task.isCancelled, stashKey == committedKey else {
            // This editor has moved on, so none of the edit-state transitions
            // below apply to what it now shows. The save did land for the field
            // it was started on, though, so that field's stash must still go or
            // returning to it reopens stale editing over saved text (#1193).
            if saved {
                InlineEditDrafts.shared.clear(for: committedKey)
            }
            return
        }

        // On failure the detail view surfaces the error in its alert; keep the
        // editor open so the unsaved text isn't lost.
        if saved {
            // The view can unmount while the save is in flight, in which case
            // `onDisappear` already stashed the draft; a save that then succeeds
            // must clear that stash, or returning later reopens stale editing
            // over the now-saved source (#1193).
            InlineEditDrafts.shared.clear(for: stashKey)
            editing = false
            focused = false
            sourceChanged = false
        } else if text != baseText {
            // Re-evaluate the conflict after the await: the source can be replaced
            // while the request is in flight, and a retried Save must present as
            // "Save Anyway" against the new base, never as a clean save (#1197).
            baseText = text
            sourceChanged = draft != text
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
