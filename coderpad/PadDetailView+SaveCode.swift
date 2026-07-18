//
//  PadDetailView+SaveCode.swift
//  coderpad
//

#if os(macOS)
    import AppKit
#else
    import UIKit
    import UniformTypeIdentifiers
#endif
import SwiftUI

extension PadDetailView {
    /// One file to write to disk, with a relative path that preserves any
    /// project folder structure (e.g. `src/main.rs`) so multi-file pads round-trip.
    private struct SavableFile {
        let relativePath: String
        let contents: String
    }

    /// Whether there is any code to save yet. Environments load asynchronously,
    /// so this stays false (disabling the menu item) until at least one carries
    /// files — or, for a legacy pad, until its inline `contents` is available.
    var hasSavableCode: Bool {
        if environments.contains(where: { !displayFiles(for: $0).isEmpty }) { return true }
        return !(pad.contents ?? "").isEmpty
    }

    /// The pad's title, falling back to its ID, used to name the saved file or
    /// folder. Never empty.
    private var suggestedBaseName: String {
        let title = pad.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? pad.id : title
    }

    /// Every file the detail view renders, flattened for saving. When several
    /// environments carry code, each is namespaced into its own subfolder so
    /// identically-named files (a candidate and a reference `main.py`) don't
    /// overwrite each other. Falls back to the legacy inline `contents` when no
    /// environment provided any files.
    private func savableFiles() -> [SavableFile] {
        let envs = environments.filter { !displayFiles(for: $0).isEmpty }
        let namespacePerEnvironment = envs.count > 1
        var result: [SavableFile] = []
        for (index, env) in envs.enumerated() {
            let prefix: String
            if namespacePerEnvironment {
                let label = env.language.flatMap { $0.isEmpty ? nil : $0 } ?? "environment"
                prefix = "\(Self.sanitizeComponent(label))-\(index + 1)/"
            } else {
                prefix = ""
            }
            for file in displayFiles(for: env) {
                result.append(SavableFile(relativePath: prefix + Self.relativePath(for: file),
                                          contents: file.contents))
            }
        }
        if result.isEmpty, let contents = pad.contents, !contents.isEmpty {
            let ext = Self.fileExtension(forLanguage: pad.language)
            result.append(SavableFile(relativePath: "\(Self.sanitizeComponent(suggestedBaseName)).\(ext)",
                                      contents: contents))
        }
        return Self.withUniqueRelativePaths(result)
    }

    /// The pad's code as printable sections — one per file, titled by its path,
    /// namespaced by environment so identically-named files across environments
    /// don't collide. Falls back to the legacy inline `contents` when no
    /// environment carries files, mirroring Save All Code. Shared by File ▸ Print and
    /// the Markdown export (#524).
    func printFiles() -> [PadPrintFile] {
        var result: [PadPrintFile] = []
        for (index, env) in environments.enumerated() {
            for file in displayFiles(for: env) {
                let title = file.path.flatMap { $0.isEmpty ? nil : $0 } ?? "Code"
                result.append(PadPrintFile(id: "\(index)-\(file.id)", title: title,
                                           code: file.contents, language: file.language ?? env.language))
            }
        }
        if result.isEmpty, let contents = pad.contents, !contents.isEmpty {
            result.append(PadPrintFile(id: "contents", title: "Code", code: contents, language: pad.language))
        }
        return result
    }

    /// Renders the pad as a single Markdown document — its summary plus each code file in a
    /// fenced block (#524) — and routes the title and metadata through a hard copy on
    /// macOS's `File ▸ Print` "Save as PDF". Shared by both platforms' export entry points.
    func printPadDocument() {
        printDocument(
            PadPrintDocument(pad: pad, files: printFiles(), displayName: directory.display),
            jobTitle: pad.title.isEmpty ? pad.id : pad.title
        )
    }

    /// Writes the pad as a single Markdown document — its summary plus each code file in a
    /// fenced block (#524). On macOS this prompts with an `NSSavePanel`; on iOS it stages a
    /// document for `.fileExporter`. The PDF half of "export" is covered by Print's
    /// "Save as PDF".
    func exportMarkdown() {
        let name = pad.title.isEmpty ? pad.id : pad.title
        let document = padMarkdownDocument(
            title: name,
            summary: padSummaryRows(pad, displayName: directory.display),
            files: printFiles()
        )

        #if os(macOS)
            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            // The title is remote content: sanitize the suggested filename like the
            // iOS branch below already does (#1162).
            panel.nameFieldStringValue = "\(Self.sanitizeComponent(name)).md"
            panel.message = "Export \"\(name)\" as Markdown"
            guard panel.runModal() == .OK, let url = panel.url else { return }

            do {
                try document.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                mutateError = error.localizedDescription
            }
        #else
            pendingExport = PadExportDocument(
                text: document,
                contentType: .plainText,
                defaultName: "\(Self.sanitizeComponent(name)).md"
            )
        #endif
    }

    /// Prompts for a destination and writes the pad's code there. A single file
    /// uses a save panel (the user names the file); multiple files use a folder
    /// chooser, then write into a subfolder named after the pad with their
    /// project structure intact.
    func saveCodeLocally() {
        let files = savableFiles()
        guard !files.isEmpty else {
            mutateError = "This pad has no code to save."
            return
        }

        #if os(macOS)
            do {
                if files.count == 1 {
                    let panel = NSSavePanel()
                    panel.canCreateDirectories = true
                    panel.nameFieldStringValue = URL(fileURLWithPath: files[0].relativePath).lastPathComponent
                    panel.message = "Save the code from \"\(suggestedBaseName)\""
                    guard panel.runModal() == .OK, let url = panel.url else { return }

                    try files[0].contents.write(to: url, atomically: true, encoding: .utf8)
                } else {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.canCreateDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.prompt = "Save"
                    panel.message = "Choose where to save the \(files.count) files from \"\(suggestedBaseName)\""
                    guard panel.runModal() == .OK, let directory = panel.url else { return }

                    let root = directory.appending(path: Self.sanitizeComponent(suggestedBaseName))
                    guard confirmReplacingExport(at: root) else { return }

                    try replaceExport(files, at: root)
                }
            } catch {
                mutateError = error.localizedDescription
            }
        #else
            // A single file exports as a plain document the user names; several files
            // export as a `.zip` named after the pad, with each file's project structure
            // preserved inside — mirroring the macOS save-panel / open-panel split.
            if files.count == 1 {
                pendingExport = PadExportDocument(
                    text: files[0].contents,
                    contentType: .plainText,
                    defaultName: URL(fileURLWithPath: files[0].relativePath).lastPathComponent
                )
            } else if let archive = PadExportDocument(
                zipName: Self.sanitizeComponent(suggestedBaseName),
                files: files.map { ($0.relativePath, $0.contents) }
            ) {
                pendingExport = archive
            } else {
                mutateError = "Could not prepare the pad's files for export."
            }
        #endif
    }

    #if os(macOS)
        private func confirmReplacingExport(at root: URL) -> Bool {
            guard FileManager.default.fileExists(atPath: root.path) else { return true }

            let alert = NSAlert()
            alert.messageText = "Replace Existing Export?"
            alert.informativeText = "\"\(root.lastPathComponent)\" already exists. "
                + "Replacing it removes old exported files before saving the current pad code."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Replace")
            alert.addButton(withTitle: "Cancel")
            return alert.runModal() == .alertFirstButtonReturn
        }

        /// Stage the complete export in a temporary sibling folder, then replace the final
        /// root so files removed from the pad do not linger from an older export.
        private func replaceExport(_ files: [SavableFile], at root: URL) throws {
            let fileManager = FileManager.default
            let parent = root.deletingLastPathComponent()
            let staging = parent.appending(path: ".\(root.lastPathComponent)-\(UUID().uuidString).tmp")
            do {
                try write(files, into: staging)
                if fileManager.fileExists(atPath: root.path) {
                    _ = try fileManager.replaceItemAt(root, withItemAt: staging)
                } else {
                    try fileManager.moveItem(at: staging, to: root)
                }
            } catch {
                try? fileManager.removeItem(at: staging)
                throw error
            }
        }

        /// Write each file into `root`, creating intermediate folders so the
        /// pad's project structure survives.
        private func write(_ files: [SavableFile], into root: URL) throws {
            let fileManager = FileManager.default
            for file in files {
                let destination = root.appending(path: file.relativePath)
                try fileManager.createDirectory(at: destination.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
                try file.contents.write(to: destination, atomically: true, encoding: .utf8)
            }
        }
    #endif

    /// A file's path with each component made filesystem-safe, preserving the
    /// `/` separators so folder structure survives. Drops empty and `.`/`..`
    /// components so a malformed path can't escape the destination folder.
    private static func relativePath(for file: CodeFile) -> String {
        if let path = file.path, !path.isEmpty {
            // Explicitly-typed intermediates keep each step cheap to type-check: the
            // chained map/filter inference otherwise blows the 250ms budget on CI's
            // slower toolchain (#427).
            let rawComponents: [String] = path.split(separator: "/").map(String.init)
            let components: [String] = rawComponents
                .filter { $0 != "." && $0 != ".." }
                .map { sanitizeComponent($0) }
                .filter { !$0.isEmpty }
            if !components.isEmpty {
                return components.joined(separator: "/")
            }
        }
        return "untitled-\(file.id).\(fileExtension(forLanguage: file.language))"
    }

    private static func withUniqueRelativePaths(_ files: [SavableFile]) -> [SavableFile] {
        let paths = uniqueRelativePaths(files.map(\.relativePath))
        return zip(files, paths).map { file, path in
            SavableFile(relativePath: path, contents: file.contents)
        }
    }

    /// Maps each known language code to a file extension. A table rather than a
    /// `switch` so the lookup stays a single statement and several aliases can map
    /// to the same extension without one giant branch.
    private static let extensionByLanguage: [String: String] = [
        "python": "py", "python2": "py", "python3": "py",
        "javascript": "js", "node": "js", "node.js": "js", "nodejs": "js",
        "typescript": "ts", "swift": "swift",
        "go": "go", "golang": "go", "rust": "rs", "java": "java",
        "kotlin": "kt", "scala": "scala", "ruby": "rb", "c": "c",
        "cpp": "cpp", "c++": "cpp", "csharp": "cs", "c#": "cs",
        "objective-c": "m", "objc": "m", "php": "php",
        "html": "html", "css": "css",
        "sql": "sql", "mysql": "sql", "postgresql": "sql", "postgres": "sql",
        "bash": "sh", "shell": "sh", "sh": "sh",
        "r": "r", "elixir": "ex", "erlang": "erl", "haskell": "hs",
        "perl": "pl", "lua": "lua", "dart": "dart", "clojure": "clj",
        "ocaml": "ml", "f#": "fs", "fsharp": "fs"
    ]

    /// A reasonable file extension for code that has no path of its own (a
    /// legacy single-file pad), derived from its language.
    private static func fileExtension(forLanguage language: String?) -> String {
        var lowered = (language ?? "").lowercased()
        if lowered.hasPrefix("multifile_") {
            lowered = String(lowered.dropFirst("multifile_".count))
        }
        return extensionByLanguage[lowered] ?? "txt"
    }
}

extension FocusedValues {
    /// Whether the focused pad's detail pane has any code to save yet, published by
    /// `PadDetailView` so the Pad menu's "Save All Code…" command disables until at least
    /// one environment (or a legacy pad's inline contents) has loaded. `nil` when no
    /// pad detail is frontmost.
    @Entry var padHasSavableCode: Bool?
}

#if !os(macOS)
    /// A staged export for the iPad's `.fileExporter`, always a single file: a one-file
    /// pad (or the Markdown export) exports as plain text the user names; a multi-file pad
    /// exports as a `.zip` whose entries preserve the pad's project folder structure.
    ///
    /// A single file (rather than a directory `FileWrapper`) is deliberate: SwiftUI's
    /// `.fileExporter` writes a directory document to a same-named temporary path and
    /// throws "a file with the same name already exists" when a prior export of the same
    /// pad lingers there. Zipping keeps every export on the robust single-file path.
    struct PadExportDocument: FileDocument {
        static var readableContentTypes: [UTType] {
            []
        }

        static var writableContentTypes: [UTType] {
            [.plainText, .zip]
        }

        /// The content type handed to `.fileExporter` — `.plainText` for a single file,
        /// `.zip` for a multi-file pad.
        let contentType: UTType
        /// The default name the export sheet pre-fills (including the extension).
        let defaultName: String
        private let data: Data

        /// A single text file the user names in the export sheet.
        init(text: String, contentType: UTType, defaultName: String) {
            self.contentType = contentType
            self.defaultName = defaultName
            data = Data(text.utf8)
        }

        /// A multi-file pad zipped into one archive named after the pad, each file at its
        /// relative path (e.g. `src/main.rs`) so the project structure survives. Returns
        /// `nil` if the archive can't be built (the caller surfaces an error).
        init?(zipName: String, files: [(path: String, contents: String)]) {
            guard let archive = Self.zipData(folderName: zipName, files: files) else { return nil }

            contentType = .zip
            defaultName = "\(zipName).zip"
            data = archive
        }

        init(configuration _: ReadConfiguration) throws {
            throw CocoaError(.featureUnsupported)
        }

        func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
            FileWrapper(regularFileWithContents: data)
        }

        /// Writes the files into a uniquely-named temporary folder, then uses
        /// `NSFileCoordinator`'s `.forUploading` option (Foundation's built-in zip) to
        /// archive it, returning the archive bytes. Cleans up the scratch directory.
        private static func zipData(folderName: String,
                                    files: [(path: String, contents: String)]) -> Data? {
            let fileManager = FileManager.default
            let scratch = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let folder = scratch.appendingPathComponent(folderName)
            defer { try? fileManager.removeItem(at: scratch) }

            do {
                for file in files {
                    let destination = folder.appending(path: file.path)
                    try fileManager.createDirectory(at: destination.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
                    try Data(file.contents.utf8).write(to: destination)
                }
            } catch {
                return nil
            }

            var archive: Data?
            var coordinationError: NSError?
            NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading,
                                           error: &coordinationError) { zippedURL in
                archive = try? Data(contentsOf: zippedURL)
            }
            return archive
        }
    }
#endif
