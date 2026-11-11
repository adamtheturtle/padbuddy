//
//  QuestionStarterFiles+Editors.swift
//  coderpad
//
//
//  The starter-file and ZIP editing surfaces; the models live alongside.

import Darwin
import os
import SwiftUI
import UniformTypeIdentifiers

struct QuestionStarterFilesEditor: View {
    @Binding var files: [QuestionStarterFileDraft]
    var replacingExisting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(replacingExisting ? "Replace starter files" : "Starter files", systemImage: "folder")
                .font(.headline)
            Text(guidance)
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach($files) { $file in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("Path, for example src/main.py", text: $file.path)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Starter file path")
                        Button(role: .destructive) {
                            files.removeAll { $0.id == file.id }
                        } label: {
                            Label("Remove File", systemImage: "trash")
                        }
                        .labelStyle(.iconOnly)
                    }
                    TextEditor(text: Binding(
                        get: { file.contents },
                        set: { proposed in
                            let otherBytes = files.lazy
                                .filter { $0.id != file.id }
                                .reduce(0) { $0 + min($1.contents.utf8.count,
                                                      QuestionStarterFileDraft.maximumContentBytes) }
                            let available = max(
                                0, QuestionStarterFileDraft.maximumAggregateContentBytes - otherBytes
                            )
                            file.contents = proposed.utf8Prefix(maximumBytes: min(
                                available, QuestionStarterFileDraft.maximumContentBytes
                            ))
                        }
                    ))
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 110)
                    .accessibilityLabel(
                        "Contents of \(file.path.isEmpty ? String(localized: "Untitled file") : file.path)"
                    )
                }
                .padding(10)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }

            Button {
                files.appendStarterFileIfPossible()
            } label: {
                Label("Add Starter File", systemImage: "doc.badge.plus")
            }
            .disabled(files.count >= QuestionStarterFileDraft.maximumCount)

            if files.hasInvalidStarterFilePaths {
                Label("Every starter file needs a unique, non-empty path.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var guidance: String {
        replacingExisting
            ? String(localized: """
            This ordered set replaces all current project files. Include every text file you want to keep.
            """)
            : String(localized: """
            Add ordered project paths and text. Nested paths, empty files, and Unicode are preserved.
            """)
    }
}
