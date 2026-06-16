//
//  SmartFilterSheet.swift
//  coderpad
//

import SwiftUI

/// A small sheet that takes a natural-language query and asks the on-device
/// interpreter to turn it into filters. Shared by the pad and question lists so
/// the two stay identical; each supplies its own placeholder and submit handler.
/// See `SearchInterpreter`.
struct SmartFilterSheet: View {
    @Binding var text: String
    let isInterpreting: Bool
    /// True after an attempt that the model couldn't map to any filter, so the
    /// sheet can explain why nothing changed instead of silently closing.
    let failed: Bool
    let placeholder: LocalizedStringKey
    let onSubmit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Smart Filter", systemImage: "sparkles").font(.title3.bold())
            TextField("", text: $text, prompt: Text(placeholder), axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2 ... 4)
                .onSubmit(onSubmit)
            if failed {
                Label("Couldn't turn that into filters. Try naming a language, owner, state, or date.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                Button(action: onSubmit) {
                    if isInterpreting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Apply")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isInterpreting || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 420)
    }
}
