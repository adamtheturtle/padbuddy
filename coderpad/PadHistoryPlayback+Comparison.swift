//
//  PadHistoryPlayback+Comparison.swift
//  coderpad
//

import SwiftUI

extension HistoryPlaybackView {
    var compareButton: some View {
        Button { showCurrentComparison = true } label: {
            Image(systemName: "rectangle.split.2x1")
                .frame(width: 24, height: 24)
        }
        .help("Compare this revision to current")
        .accessibilityLabel("Compare this revision to current")
        .disabled(displayedSnapshot == nil || position >= timeline.items.count - 1)
    }

    @ViewBuilder
    var comparisonViewer: some View {
        if let file = displayedFile,
           let snapshot = displayedSnapshot,
           let historical = file.contents(at: snapshot.index),
           let latestIndex = file.snapshots.indices.last,
           let current = file.contents(at: latestIndex) {
            VStack(spacing: 0) {
                HStack {
                    Text("Revision \(position + 1)").font(.headline)
                    Spacer()
                    Text("Current").font(.headline)
                    Spacer()
                    Button("Done") { showCurrentComparison = false }
                        .keyboardShortcut(.cancelAction)
                }
                .padding()
                Divider()
                HStack(spacing: 0) {
                    HighlightedCode(contents: historical, language: file.language, dark: dark, fillsHeight: true)
                    Divider()
                    HighlightedCode(contents: current, language: file.language, dark: dark, fillsHeight: true)
                }
            }
            .frame(minWidth: 760, minHeight: 560)
        } else {
            ContentUnavailableView("Comparison Unavailable", systemImage: "rectangle.split.2x1")
        }
    }
}
