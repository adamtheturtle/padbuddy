//
//  PadHistoryPlayback+Context.swift
//  coderpad
//
//  Labels and file selection that explain the playback tracks.
//

import SwiftUI

extension HistoryPlaybackView {
    var filePicker: some View {
        Picker("File", selection: fileSelection) {
            ForEach(histories) { history in
                Text(history.title).tag(history.id)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: 260, alignment: .leading)
        .accessibilityLabel("History file")
    }

    func trackLabel(_ title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption.weight(.semibold))
            Text(detail).font(.caption2).foregroundStyle(.secondary)
        }
    }

    /// Picking a file views it as of the current playhead without moving the
    /// playhead; the next scrub or step goes back to following the edits.
    private var fileSelection: Binding<String> {
        Binding {
            displayedFileID ?? histories.first?.id ?? ""
        } set: { newValue in
            manualFileID = newValue
        }
    }
}
