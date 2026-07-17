//
//  PadCodePreview+Export.swift
//  coderpad
//
//  Saving an environment's code to disk: the macOS save-panel download actions
//  (single file, or a whole multi-file project as a folder) and the iOS
//  FileDocument used by the fileExporter. Split from PadCodePreview.swift /
//  PadCodePreview+Card.swift to keep both within the lint length limit.
//

#if os(macOS)
    import AppKit
#endif
import SwiftUI
import UniformTypeIdentifiers

enum CodeExportPathError: LocalizedError {
    case fileDirectoryConflict(String)

    var errorDescription: String? {
        switch self {
        case let .fileDirectoryConflict(path):
            "Cannot export files because \"\(path)\" is both a file and a folder."
        }
    }
}

/// Pure path planning, `nonisolated` so the iOS `FileDocument` (whose conformance is
/// nonisolated) can call it off the main actor; the module default would pin it there.
nonisolated enum CodeExportPathPlan {
    static func components(for file: CodeFile) -> [String] {
        let path = file.path ?? file.name
        var components: [String] = []

        for component in path.split(separator: "/") {
            let name = String(component)
            guard !name.isEmpty, name != ".", name != ".." else { continue }

            components.append(name)
        }

        return components.isEmpty ? [file.name] : components
    }

    static func validateNoFileDirectoryConflicts(_ files: [CodeFile]) throws {
        var filePaths = Set<String>()
        var directoryPaths = Set<String>()

        for file in files {
            let components = components(for: file)
            let filePath = components.joined(separator: "/")
            if directoryPaths.contains(filePath) {
                throw CodeExportPathError.fileDirectoryConflict(filePath)
            }

            var directoryComponents: [String] = []
            for component in components.dropLast() {
                directoryComponents.append(component)
                let directoryPath = directoryComponents.joined(separator: "/")
                if filePaths.contains(directoryPath) {
                    throw CodeExportPathError.fileDirectoryConflict(directoryPath)
                }
                directoryPaths.insert(directoryPath)
            }

            filePaths.insert(filePath)
        }
    }
}

extension EnvironmentCodeCard {
    /// Writes the file's contents to a user-chosen location. The save panel
    /// grants the sandboxed app write access to the picked URL, so no extra
    /// entitlement beyond user-selected read-write is needed.
    func download(_ file: CodeFile) {
        #if os(macOS)
            let panel = NSSavePanel()
            panel.nameFieldStringValue = file.name
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false
            guard panel.runModal() == .OK, let url = panel.url else { return }

            do {
                try file.contents.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                // A failed export must not close silently as if it saved (#791).
                exportError = error.localizedDescription
            }
        #else
            // iPad export (a document picker / share sheet) can be added later; for now
            // this is a no-op so the download button stays present but inert on iOS.
        #endif
    }

    /// Saves every file in the environment into a folder chosen via a save panel
    /// pre-filled with the pad id. Each file keeps its relative path so a
    /// multi-file project lands back in its original layout. The save panel
    /// grants write access to the picked location, so the folder can be created
    /// there with no extra entitlement beyond user-selected read-write.
    func downloadAll(_ files: [CodeFile]) {
        #if os(macOS)
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "pad-\(padID)"
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let destination = panel.url else { return }

            do {
                try writeFolder(of: files, to: destination)
            } catch {
                // Writes are sequential, so a mid-write failure would leave a partial
                // folder posing as a complete download: remove it and say why (#791).
                try? FileManager.default.removeItem(at: destination)
                exportError = error.localizedDescription
            }
        #else
            // iPad export (a document picker / share sheet) can be added later; for now
            // this is a no-op so the download button stays present but inert on iOS.
        #endif
    }

    #if os(macOS)
        /// Writes the files into a fresh folder at `destination`, recreating each
        /// file's relative path beneath it.
        private func writeFolder(of files: [CodeFile], to destination: URL) throws {
            try CodeExportPathPlan.validateNoFileDirectoryConflicts(files)

            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

            for file in files {
                // Keep the file's relative path, dropping any `.`/`..` segments so a
                // crafted path can't escape the destination folder.
                let relative = CodeExportPathPlan.components(for: file).joined(separator: "/")
                let fileURL = destination.appendingPathComponent(relative.isEmpty ? file.name : relative)
                try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
                try file.contents.write(to: fileURL, atomically: true, encoding: .utf8)
            }
        }
    #endif
}

#if os(iOS)
    nonisolated struct CodeExportDocument: FileDocument {
        static var readableContentTypes: [UTType] {
            [.utf8PlainText, .folder]
        }

        static var writableContentTypes: [UTType] {
            [.utf8PlainText, .folder]
        }

        let files: [CodeFile]
        let defaultFilename: String
        let contentType: UTType

        init(files: [CodeFile], defaultFilename: String, contentType: UTType) {
            self.files = files
            self.defaultFilename = defaultFilename
            self.contentType = contentType
        }

        init(configuration _: ReadConfiguration) throws {
            throw CocoaError(.fileReadUnsupportedScheme)
        }

        func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
            if contentType == .folder || files.count > 1 {
                return CodeExportDirectory(files: files).fileWrapper()
            }

            let file = files.first ?? .placeholder
            let wrapper = FileWrapper(regularFileWithContents: Data(file.contents.utf8))
            wrapper.preferredFilename = file.name
            return wrapper
        }
    }

    private final nonisolated class CodeExportDirectory {
        private var filesByName: [String: FileWrapper] = [:]
        private var directoriesByName: [String: CodeExportDirectory] = [:]
        private var directoryAliasesByName: [String: String] = [:]

        init(files: [CodeFile] = []) {
            for file in files {
                insert(file, components: Self.pathComponents(for: file))
            }
        }

        func fileWrapper() -> FileWrapper {
            var children: [String: FileWrapper] = filesByName
            for (name, directory) in directoriesByName {
                let wrapper = directory.fileWrapper()
                wrapper.preferredFilename = name
                children[name] = wrapper
            }
            return FileWrapper(directoryWithFileWrappers: children)
        }

        private func insert(_ file: CodeFile, components: [String]) {
            guard let name = components.first else { return }

            if components.count == 1 {
                let unique = uniqueName(name)
                let wrapper = FileWrapper(regularFileWithContents: Data(file.contents.utf8))
                wrapper.preferredFilename = unique
                filesByName[unique] = wrapper
                return
            }

            let directoryName = directoryName(for: name)
            let directory = directoriesByName[directoryName] ?? CodeExportDirectory()
            directoriesByName[directoryName] = directory
            directory.insert(file, components: Array(components.dropFirst()))
        }

        private func directoryName(for preferred: String) -> String {
            if let alias = directoryAliasesByName[preferred] {
                return alias
            }

            let alias = uniqueName(preferred)
            directoryAliasesByName[preferred] = alias
            return alias
        }

        private func uniqueName(_ preferred: String) -> String {
            var candidate = preferred
            var index = 2
            while filesByName[candidate] != nil || directoriesByName[candidate] != nil {
                candidate = "\(preferred) \(index)"
                index += 1
            }
            return candidate
        }

        private static func pathComponents(for file: CodeFile) -> [String] {
            CodeExportPathPlan.components(for: file)
        }
    }
#endif
