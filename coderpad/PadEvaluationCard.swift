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

    var body: some View {
        DetailSection(title: "Evaluation", systemImage: "checklist") {
            VStack(alignment: .leading, spacing: 12) {
                ratingRow
                tagsRow
                notesRow
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
        var seen = Set<String>()
        return tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    // MARK: - Notes

    private var notesRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Notes")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextEditor(text: $notes)
                .font(.callout)
                .frame(minHeight: 90)
                .padding(6)
                .background(Color.subtleStroke.opacity(0.5),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if notes.isEmpty {
                        Text("Private notes for this pad…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 14)
                            .allowsHitTesting(false)
                    }
                }
        }
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
