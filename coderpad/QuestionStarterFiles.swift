import SwiftUI

struct QuestionStarterFileDraft: Codable, Equatable, Identifiable {
    var id = UUID()
    var path = ""
    var contents = ""

    var requestValue: QuestionFileContent {
        QuestionFileContent(path: path, contents: contents)
    }
}

extension Array where Element == QuestionStarterFileDraft {
    var hasInvalidStarterFilePaths: Bool {
        let paths = map(\.path)
        return paths.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            || Set(paths).count != paths.count
    }
}

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
                    TextEditor(text: $file.contents)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 110)
                        .accessibilityLabel("Contents of \(file.path.isEmpty ? "starter file" : file.path)")
                }
                .padding(10)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }

            Button {
                files.append(QuestionStarterFileDraft())
            } label: {
                Label("Add Starter File", systemImage: "doc.badge.plus")
            }

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
            CoderPad does not return the current project files. This ordered set will replace them.
            """)
            : String(localized: """
            Add ordered project paths and text. Nested paths, empty files, and Unicode are preserved.
            """)
    }
}

struct QuestionStarterFilesReplacementSheet: View {
    let replace: ([QuestionFileContent]) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var files = [QuestionStarterFileDraft()]
    @State private var isSubmitting = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                QuestionStarterFilesEditor(files: $files, replacingExisting: true)
                    .padding()
            }
            .navigationTitle("Replace Starter Files")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Replace") { Task { await submit() } }
                        .disabled(isSubmitting || files.isEmpty || files.hasInvalidStarterFilePaths)
                }
            }
            .overlay {
                if isSubmitting { ProgressView() }
            }
            .alert("Could Not Replace Starter Files", isPresented: .constant(error != nil)) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
        .frame(minWidth: 620, minHeight: 520)
        .interactiveDismissDisabled(isSubmitting)
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await replace(files.map(\.requestValue))
            dismiss()
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }
}
