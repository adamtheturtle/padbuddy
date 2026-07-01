//
//  PadEvaluationCard.swift
//  coderpad
//
//  The pad detail pane's "Evaluation" section (#591): an interviewer-private rating,
//  notes, and tags for the pad, persisted locally via ``PadEvaluationStore``. Edits
//  autosave so a note is never lost to a missed Save button. The detail view reuses one
//  instance across pads, so the draft reloads whenever `padID` changes.
//

import SwiftUI

struct PadEvaluationCard: View {
    let padID: String

    @State private var store = PadEvaluationStore.shared
    @State private var rating = 0
    @State private var notes = ""
    @State private var tagsText = ""
    /// The pad whose evaluation is currently loaded into the drafts above, so a save
    /// triggered mid-reload can't write one pad's text onto another's record.
    @State private var loadedPadID: String?
    /// The user-chosen height of the notes editor, set by dragging the corner handle.
    /// Clamped to ``Self.notesMinHeight``...``Self.notesMaxHeight`` so it can grow for a
    /// long write-up but never collapse away or run off the pane.
    @State private var notesHeight = Self.notesMinHeight
    /// The editor height when the active resize drag began, so each drag applies its
    /// translation relative to where the handle was grabbed.
    @State private var notesHeightAtDragStart: CGFloat?

    private static let notesMinHeight: CGFloat = 90
    private static let notesMaxHeight: CGFloat = 600

    var body: some View {
        DetailSection(title: "Evaluation", systemImage: "checklist") {
            VStack(alignment: .leading, spacing: 12) {
                ratingRow
                tagsRow
                notesRow
                privacyNote
            }
        }
        .onChange(of: padID, initial: true) { _, _ in load() }
        .onChange(of: rating) { _, _ in save() }
        .onChange(of: notes) { _, _ in save() }
        .onChange(of: tagsText) { _, _ in save() }
    }

    // MARK: - Rating

    private var ratingRow: some View {
        HStack(spacing: 8) {
            Text("Rating")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 4) {
                ForEach(1 ... 5, id: \.self) { value in
                    Button {
                        // Tapping the current rating clears it, so a misclick is undoable
                        // without a separate control.
                        rating = (rating == value) ? 0 : value
                    } label: {
                        Image(systemName: value <= rating ? "star.fill" : "star")
                            .foregroundStyle(value <= rating ? .yellow : .secondary)
                    }
                    .buttonStyle(.plain)
                    // Five tiny icon-only stars 4pt apart are unreliable to hit on
                    // touch; give each a 44pt target (no-op on macOS, #597). The 44pt
                    // frames sit side by side so adjacent ratings no longer overlap.
                    .touchTarget()
                    // Highlight each star under the iPad pointer (#586).
                    .pointerHoverEffect()
                    .help("Rate \(value) of 5")
                    .accessibilityLabel("Rate \(value) of 5")
                }
            }
        }
    }

    // MARK: - Tags

    private var tagsRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tags")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextField("Comma-separated, e.g. strong, follow-up", text: $tagsText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
            if !parsedTags.isEmpty {
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(parsedTags, id: \.self) { tag in
                        Chip(text: tag)
                    }
                }
            }
        }
    }

    /// The tags as the store will persist them: trimmed, non-empty, de-duplicated while
    /// keeping the order the user typed them in.
    private var parsedTags: [String] {
        PadEvaluation.parseTags(from: tagsText)
    }

    // MARK: - Notes

    private var notesRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Notes")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextEditor(text: $notes)
                .font(.callout)
                .frame(height: notesHeight)
                .padding(6)
                .background(Color.subtleStroke.opacity(0.5),
                            in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if notes.isEmpty {
                        Text("Private notes for this pad…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .bottom) {
                    notesResizeHandle
                }
        }
    }

    /// A grabber bar centred along the editor's bottom edge. Dragging it up or down
    /// resizes the notes area, clamped so it stays usable.
    ///
    /// The drag is measured in the `.global` coordinate space: the handle moves as the
    /// editor grows, so a handle-local translation would feed back on itself and jitter.
    private var notesResizeHandle: some View {
        Capsule()
            .fill(.secondary)
            .frame(width: 36, height: 5)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            // Declarative vertical-resize cursor on hover (macOS-only: iPadOS has no
            // equivalent pointer-shape API here).
            #if os(macOS)
            .pointerStyle(.rowResize)
            #endif
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        let start = notesHeightAtDragStart ?? notesHeight
                        notesHeightAtDragStart = start
                        notesHeight = min(
                            max(start + value.translation.height, Self.notesMinHeight),
                            Self.notesMaxHeight
                        )
                    }
                    .onEnded { _ in notesHeightAtDragStart = nil }
            )
            .accessibilityLabel("Resize notes")
    }

    // MARK: - Privacy note

    /// Makes it explicit that this evaluation is the interviewer's private scratch data:
    /// it syncs across their own devices through iCloud but is never written back to
    /// CoderPad, so a private rating and notes can't leak into the shared pad on the service.
    private var privacyNote: some View {
        let message: LocalizedStringKey =
        "Private to you. Ratings, tags, and notes sync across your devices via iCloud and are never sent to CoderPad."
        return Label(message, systemImage: "lock.fill")
        .font(.caption)
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 2)
    }

    // MARK: - Load / save

    private func load() {
        let evaluation = store.evaluation(for: padID)
        rating = evaluation.rating
        notes = evaluation.notes
        tagsText = evaluation.tags.joined(separator: ", ")
        loadedPadID = padID
    }

    private func save() {
        // Skip the save the reload itself triggers, and never write one pad's drafts
        // onto another's record while `padID` is changing.
        guard loadedPadID == padID else { return }

        store.setEvaluation(
            PadEvaluation(rating: rating, notes: notes, tags: parsedTags),
            for: padID
        )
    }
}
