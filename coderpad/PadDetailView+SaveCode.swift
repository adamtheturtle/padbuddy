//
//  PadDetailView+SaveCode.swift
//  coderpad
//

#if os(macOS)
    import AppKit
#else
    import UIKit
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
        return result
    }

    /// The pad's code as printable sections — one per file, titled by its path,
    /// namespaced by environment so identically-named files across environments
    /// don't collide. Falls back to the legacy inline `contents` when no
    /// environment carries files, mirroring Save Code. Shared by File ▸ Print and
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

    /// Prompts for a destination and writes the pad as a single Markdown document — its
    /// summary plus each code file in a fenced block (#524). The PDF half of "export" is
    /// already covered by File ▸ Print's "Save as PDF".
    func exportMarkdown() {
        #if os(macOS)
            let name = pad.title.isEmpty ? pad.id : pad.title
            let document = padMarkdownDocument(
                title: name,
                summary: padSummaryRows(pad, displayName: directory.display),
                files: printFiles()
            )

            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = "\(name).md"
            panel.message = "Export \"\(name)\" as Markdown"
            guard panel.runModal() == .OK, let url = panel.url else { return }

            do {
                try document.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                mutateError = error.localizedDescription
            }
        #else
            // TODO: iPad via .fileExporter/.fileImporter
        #endif
    }

    /// Prompts for a destination and writes the pad's code there. A single file
    /// uses a save panel (the user names the file); multiple files use a folder
    /// chooser, then write into a subfolder named after the pad with their
    /// project structure intact.
    func saveCodeLocally() {
        #if os(macOS)
            let files = savableFiles()
            guard !files.isEmpty else {
                mutateError = "This pad has no code to save."
                return
            }

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
                    let fileManager = FileManager.default
                    for file in files {
                        let destination = root.appending(path: file.relativePath)
                        try fileManager.createDirectory(at: destination.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                        try file.contents.write(to: destination, atomically: true, encoding: .utf8)
                    }
                }
            } catch {
                mutateError = error.localizedDescription
            }
        #else
            // TODO: iPad via .fileExporter/.fileImporter
        #endif
    }

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

    /// Replaces characters that are unsafe in a single path component, so a pad
    /// title or file name can't break out of its folder or confuse the shell.
    private static func sanitizeComponent(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "untitled" : cleaned
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
    /// `PadDetailView` so the Pad menu's "Save Code…" command disables until at least
    /// one environment (or a legacy pad's inline contents) has loaded. `nil` when no
    /// pad detail is frontmost.
    @Entry var padHasSavableCode: Bool?
}
