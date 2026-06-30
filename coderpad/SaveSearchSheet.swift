//
//  SaveSearchSheet.swift
//  coderpad
//
//  The "Save Search" sheet, shared by the Pads and Questions filter bars. Both
//  presented the same form by hand: a name field (clamped to the saved-search name
//  limit, committing on Return), an optional on-device name-suggestion button, and
//  Cancel/Save actions with Save disabled until the name is non-empty. Only the
//  field's prompt and the commit/suggest actions differ, so those are passed in.
//

import SwiftUI

struct SaveSearchSheet: View {
    @Binding var name: String
    /// The text field's placeholder, naming the section's flavor of saved search
    /// (e.g. "e.g. Live pads, my team" vs "e.g. My drafts, Python").
    var prompt: Text
    /// Whether to offer the sparkle name-suggestion button — true only when the
    /// on-device model is available (see `SavedSearchNamer.isAvailable`).
    var showsSuggest: Bool
    /// True while a suggestion is being generated, which swaps the sparkle for a
    /// spinner and disables the button.
    var isSuggesting: Bool
    var onSuggest: () -> Void
    var onCommit: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save Search").font(.title3.bold())
            HStack(spacing: 8) {
                TextField("Name", text: $name, prompt: prompt)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(onCommit)
                    // Clamp to the same limit new names are capped at on save, so a
                    // pasted multi-line or overlong name can't overflow the field.
                    .onChange(of: name) { _, newValue in
                        if newValue.count > NamedSearch.maxNameLength {
                            name = String(newValue.prefix(NamedSearch.maxNameLength))
                        }
                    }
                if showsSuggest {
                    suggestButton
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                Button("Save", action: onCommit)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        // macOS keeps a fixed width; this small form sizes to a medium detent on iPad with
        // a drag indicator so it reads as dismissible (#610).
        #if os(macOS)
        .frame(minWidth: 360)
        #else
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        #endif
    }

    /// A sparkle button that fills the name field with an on-device suggestion built
    /// from the active filters. The field stays fully editable; the user opts in per
    /// save.
    private var suggestButton: some View {
        Button(action: onSuggest) {
            if isSuggesting {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "sparkles")
            }
        }
        .buttonStyle(.borderless)
        .disabled(isSuggesting)
        .help("Suggest a name from the current filters")
        .accessibilityLabel("Suggest a name")
    }
}
