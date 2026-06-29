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

    /// On iPad a plain `.sheet` is a fixed-size form card, so this short content
    /// would float in a large empty box. We measure the content's natural height
    /// and pin the sheet to a matching detent. macOS sheets already size to fit.
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        content
        #if os(iOS)
            .presentationDetents(contentHeight > 0 ? [.height(contentHeight)] : [.medium])
        #endif
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            VStack(alignment: .leading, spacing: 6) {
                TextField("", text: $text, prompt: Text(placeholder), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2 ... 4)
                    .font(.body)
                    .onSubmit(onSubmit)
                if failed {
                    Label("Couldn't turn that into filters. Try naming a language, owner, state, or date.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Label("Mention a language, owner, state, or date.", systemImage: "lightbulb")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            footer
        }
        .padding(20)
        .frame(minWidth: 440)
        #if os(iOS)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        #endif
    }

    /// A tinted sparkles glyph beside the title and a one-line explanation, so the
    /// sheet reads as a labelled feature rather than a bare text box.
    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Smart Filter")
                    .font(.headline)
                Text("Describe what you want in plain language and it becomes filters.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
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
}
