//
//  PadCodePreview+Export.swift
//  coderpad
//
//  Saving an environment's code to disk: the macOS save-panel download actions
//  (single file, or a whole multi-file project as a folder) and the shared path
//  planning the iOS zip export also uses. Split from PadCodePreview.swift /
//  PadCodePreview+Card.swift to keep both within the lint length limit.
//

#if os(macOS)
    import AppKit
#endif
import SwiftUI
import UniformTypeIdentifiers

enum CodeExportPathError: LocalizedError {
    case fileDirectoryConflict(String)
    case destinationNotEmpty(String)

    var errorDescription: String? {
        switch self {
        case let .fileDirectoryConflict(path):
            "Cannot export files because \"\(path)\" is both a file and a folder."
        case let .destinationNotEmpty(name):
            "\"\(name)\" already exists and isn't empty. Choose a new folder name to export into."
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

            // Sanitize each component: remotely supplied names can carry colons,
            // control characters, or bare dots that fail or misbehave differently
            // per platform once handed to the exporter (#1177).
            components.append(SaveCodePathHelpers.sanitizeComponent(name))
        }

        return components.isEmpty ? [SaveCodePathHelpers.sanitizeComponent(file.name)] : components
    }

    /// A unique relative path per file, in order: exact and case-insensitive collisions
    /// are renamed with a copy number so no file silently overwrites another on a
    /// case-insensitive volume (#1040).
    static func uniqueRelativePaths(for files: [CodeFile]) -> [String] {
        SaveCodePathHelpers.uniqueRelativePaths(
            files.map { components(for: $0).joined(separator: "/") }
        )
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

            var createdDestination = false
            do {
                try writeFolder(of: files, to: destination, createdDestination: &createdDestination)
            } catch {
                // Writes are sequential, so a mid-write failure would leave a partial
                // folder posing as a complete download: remove it and say why (#791).
                // Only a folder this export created is removed — cleanup after an
                // early validation failure must never delete a pre-existing item the
                // user happened to select (#1176).
                if createdDestination {
                    try? FileManager.default.removeItem(at: destination)
                }
                exportError = error.localizedDescription
            }
        #else
            // iPad export (a document picker / share sheet) can be added later; for now
            // this is a no-op so the download button stays present but inert on iOS.
        #endif
    }

    #if os(macOS)
        /// Writes the files into a fresh folder at `destination`, recreating each
        /// file's relative path beneath it. `createdDestination` reports whether
        /// this call created the folder, so the caller's failure cleanup can limit
        /// itself to what this export actually made (#1176).
        private func writeFolder(
            of files: [CodeFile],
            to destination: URL,
            createdDestination: inout Bool
        ) throws {
            try CodeExportPathPlan.validateNoFileDirectoryConflicts(files)

            let fileManager = FileManager.default
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: destination.path, isDirectory: &isDirectory) {
                // Never delete what the user already had: refuse a file or a
                // non-empty folder instead of silently replacing its contents when
                // the save panel's replacement prompt was bypassed or misread
                // (#1175). An existing *empty* folder is reused.
                guard isDirectory.boolValue,
                      try fileManager.contentsOfDirectory(atPath: destination.path).isEmpty else {
                    throw CodeExportPathError.destinationNotEmpty(destination.lastPathComponent)
                }
            } else {
                try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
                createdDestination = true
            }

            // Each file keeps its relative path (traversal segments already dropped by
            // the plan), renamed where paths collide exactly or by letter case only —
            // otherwise the later write would silently clobber the earlier file (#1040).
            for (file, relative) in zip(files, CodeExportPathPlan.uniqueRelativePaths(for: files)) {
                let fileURL = destination.appendingPathComponent(relative.isEmpty ? file.name : relative)
                try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
                try file.contents.write(to: fileURL, atomically: true, encoding: .utf8)
            }
        }
    #endif
}

// The iOS export used to stage a bespoke CodeExportDocument here that wrote a
// directory FileWrapper for multi-file environments; it was replaced by the shared
// zip-based PadExportDocument (see PadDetailView+SaveCode.swift), because SwiftUI's
// fileExporter fails a repeated same-name directory export and the failure was
// silent (#706).
