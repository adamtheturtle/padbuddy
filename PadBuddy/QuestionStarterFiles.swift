import Darwin
import SwiftUI
import UniformTypeIdentifiers

struct QuestionZIPSelection {
    nonisolated static let maximumArchiveBytes = 25 * 1024 * 1024

    let data: Data
    let filename: String

    var upload: QuestionZIPUpload {
        QuestionZIPUpload(data: data, filename: filename)
    }

    static func load(from url: URL) async throws -> Self {
        try await Task.detached {
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let data = try loadBoundedRegularFile(from: url)
            return Self(data: data, filename: url.lastPathComponent)
        }.value
    }

    private nonisolated static func loadBoundedRegularFile(from url: URL) throws -> Data {
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else {
            throw QuestionZIPSelectionError.cannotRead
        }

        defer { close(descriptor) }

        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              metadata.st_mode & S_IFMT == S_IFREG else {
            throw QuestionZIPSelectionError.notRegularFile
        }
        guard metadata.st_size >= 0,
              metadata.st_size <= maximumArchiveBytes else {
            throw QuestionZIPSelectionError.tooLarge(maximumBytes: maximumArchiveBytes)
        }

        var data = Data()
        data.reserveCapacity(Int(metadata.st_size))
        let chunkSize = 64 * 1024
        var buffer = [UInt8](repeating: 0, count: chunkSize)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            guard count >= 0 else {
                if errno == EINTR {
                    continue
                }
                throw QuestionZIPSelectionError.cannotRead
            }
            guard count > 0 else { return data }
            guard data.count <= maximumArchiveBytes - count else {
                throw QuestionZIPSelectionError.tooLarge(maximumBytes: maximumArchiveBytes)
            }

            data.append(buffer, count: count)
        }
    }
}

enum QuestionZIPSelectionError: LocalizedError, Equatable {
    case cannotRead
    case notRegularFile
    case tooLarge(maximumBytes: Int)

    var errorDescription: String? {
        switch self {
        case .cannotRead:
            String(localized: "The selected ZIP could not be read.")
        case .notRegularFile:
            String(localized: "Choose a regular ZIP file, not a folder or symbolic link.")
        case let .tooLarge(maximumBytes):
            String(localized: "Choose a ZIP file smaller than \(maximumBytes / 1024 / 1024) MB.")
        }
    }
}

struct QuestionZIPPicker: View {
    @Binding var selection: QuestionZIPSelection?
    let onSelected: () -> Void
    @State private var isImporting = false
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                isImporting = true
            } label: {
                Label(selection == nil ? "Choose Project ZIP…" : "Choose a Different ZIP…", systemImage: "archivebox")
            }
            .disabled(isLoading)
            if isLoading {
                ProgressView().controlSize(.small)
            }
            if let selection {
                Label(selection.filename, systemImage: "doc.zipper")
                    .font(.caption)
                Text("ZIP selections are kept for this sheet only and are not restored in saved drafts.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.zip]) { result in
            guard case let .success(url) = result else { return }

            isLoading = true
            error = nil
            Task {
                defer { isLoading = false }
                do {
                    selection = try await QuestionZIPSelection.load(from: url)
                    onSelected()
                } catch {
                    self.error = error.localizedDescription
                }
            }
        }
    }
}

struct QuestionStarterFileDraft: Codable, Equatable, Identifiable {
    static let maximumCount = 100

    var id = UUID()
    var path = ""
    var contents = ""

    var requestValue: QuestionFileContent {
        QuestionFileContent(path: path, contents: contents)
    }
}

extension [QuestionStarterFileDraft] {
    var hasInvalidStarterFilePaths: Bool {
        let paths = map(\.path)
        return paths.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            || Set(paths).count != paths.count
    }

    mutating func appendStarterFileIfPossible() {
        guard count < QuestionStarterFileDraft.maximumCount else { return }

        append(QuestionStarterFileDraft())
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
                if isSubmitting {
                    ProgressView()
                }
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

struct QuestionZIPReplacementSheet: View {
    let replace: (QuestionZIPUpload) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selection: QuestionZIPSelection?
    @State private var isSubmitting = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("CoderPad does not return the current project archive. The selected ZIP will replace it.")
                    .foregroundStyle(.secondary)
                QuestionZIPPicker(selection: $selection, onSelected: {})
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Replace Project ZIP")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Replace") { Task { await submit() } }
                        .disabled(isSubmitting || selection == nil)
                }
            }
            .overlay {
                if isSubmitting {
                    ProgressView()
                }
            }
        }
        .frame(minWidth: 520, minHeight: 320)
        .interactiveDismissDisabled(isSubmitting)
    }

    private func submit() async {
        guard let selection else { return }

        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await replace(selection.upload)
            dismiss()
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }
}
