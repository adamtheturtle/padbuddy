import Darwin
import os
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

        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags & ~O_NONBLOCK) == 0 else {
            throw QuestionZIPSelectionError.cannotRead
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

struct QuestionZIPPicker: View {
    private static let logger = Logger(subsystem: "com.coderpad.app", category: "question-zip-picker")
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
            guard case let .success(url) = result else {
                if case let .failure(failure) = result,
                   let message = questionZIPImportFailureMessage(failure) {
                    error = message
                    Self.logger.error("ZIP importer failed: \(failure.localizedDescription, privacy: .private)")
                }
                return
            }

            isLoading = true
            error = nil
            Task {
                defer { isLoading = false }
                do {
                    selection = try await QuestionZIPSelection.load(from: url)
                    onSelected()
                } catch {
                    if let message = questionZIPImportFailureMessage(error) {
                        self.error = message
                        Self.logger.error("ZIP read failed: \(error.localizedDescription, privacy: .private)")
                    }
                }
            }
        }
    }
}

struct QuestionStarterFileDraft: Codable, Equatable, Identifiable {
    static let maximumCount = 100
    static let maximumContentBytes = 100_000
    static let maximumAggregateContentBytes = 1_000_000

    var id = UUID()
    var path = ""
    var contents = ""

    var canonicalPath: String {
        path.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
    }

    var hasValidCanonicalPath: Bool {
        let path = canonicalPath
        guard !path.isEmpty,
              path.count <= NewQuestionSheet.Limits.starterFilePath,
              !path.hasPrefix("/"),
              !path.contains("\\"),
              !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else { return false }

        return path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
            !$0.isEmpty && $0 != "." && $0 != ".."
        }
    }

    var requestValue: QuestionFileContent {
        QuestionFileContent(path: canonicalPath, contents: contents)
    }
}

extension [QuestionStarterFileDraft] {
    var boundedForQuestionMutation: [QuestionStarterFileDraft] {
        var remainingBytes = QuestionStarterFileDraft.maximumAggregateContentBytes
        return prefix(QuestionStarterFileDraft.maximumCount).map { file in
            var bounded = file
            bounded.path = String(file.canonicalPath.prefix(NewQuestionSheet.Limits.starterFilePath))
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .precomposedStringWithCanonicalMapping
            bounded.contents = file.contents.utf8Prefix(
                maximumBytes: Swift.min(QuestionStarterFileDraft.maximumContentBytes, remainingBytes)
            )
            remainingBytes -= bounded.contents.utf8.count
            return bounded
        }
    }

    var hasInvalidStarterFilePaths: Bool {
        let bounded = boundedForQuestionMutation
        let paths = bounded.map(\.canonicalPath)
        return bounded.contains { !$0.hasValidCanonicalPath }
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

private extension String {
    func utf8Prefix(maximumBytes: Int) -> String {
        guard utf8.count > maximumBytes else { return self }

        let prefix = utf8.prefix(maximumBytes)
        if let exact = String(prefix) {
            return exact
        }
        for dropped in 1 ... min(3, maximumBytes) {
            if let valid = String(utf8.prefix(maximumBytes - dropped)) {
                return valid
            }
        }
        return ""
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
        // Claim submission synchronously before any await so queued Replace
        // actions cannot send concurrent full replacement PUTs (#4677).
        guard !isSubmitting else { return }

        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await replace(files.boundedForQuestionMutation.map(\.requestValue))
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
        // Claim submission synchronously before any await so queued Replace
        // actions cannot send concurrent whole-project archive replacements (#4690).
        guard !isSubmitting else { return }

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
