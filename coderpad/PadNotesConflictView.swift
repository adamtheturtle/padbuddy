//
//  PadNotesConflictView.swift
//  coderpad
//

import SwiftUI

struct PadNotesConflict: Identifiable {
    let id = UUID()
    let local: String
    let server: String
}

struct PadNotesConflictView: View {
    let conflict: PadNotesConflict
    let dismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("These notes changed elsewhere. Compare both versions before editing or saving again.")
                    .foregroundStyle(.secondary)

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) { comparisonCards }
                    VStack(alignment: .leading, spacing: 16) { comparisonCards }
                }
            }
            .padding()
            .navigationTitle("Notes Conflict")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 360)
    }

    @ViewBuilder
    private var comparisonCards: some View {
        comparisonCard(title: "Your Version", text: conflict.local)
        comparisonCard(title: "Server Version", text: conflict.server)
    }

    private func comparisonCard(title: LocalizedStringKey, text: String) -> some View {
        GroupBox {
            ScrollView {
                Text(text.isEmpty ? String(localized: "Empty") : text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 180)

            Button("Copy", systemImage: "doc.on.doc") { Clipboard.copy(text) }
                .frame(maxWidth: .infinity, alignment: .trailing)
        } label: {
            Text(title).font(.headline)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}
