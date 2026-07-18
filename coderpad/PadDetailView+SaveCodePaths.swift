//
//  PadDetailView+SaveCodePaths.swift
//  coderpad
//

import Foundation

extension PadDetailView {
    /// Replaces characters that are unsafe in a single path component, so a pad
    /// title or file name can't break out of its folder or confuse the shell.
    static func sanitizeComponent(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !cleaned.allSatisfy({ $0 == "." }) else {
            return "untitled"
        }

        return cleaned
    }

    static func uniqueRelativePaths(_ paths: [String]) -> [String] {
        SaveCodePathHelpers.uniqueRelativePaths(paths)
    }
}

/// Shared by the pad "Save All Code"/zip export (via `PadDetailView.uniqueRelativePaths`)
/// and the per-environment folder download (via `CodeExportPathPlan`). `nonisolated` so
/// the iOS `FileDocument` export path can call it off the main actor.
nonisolated enum SaveCodePathHelpers {
    /// Renames collisions so every returned path is unique. Uniqueness is judged
    /// case-insensitively: macOS/iOS volumes are case-insensitive by default, so
    /// `README.md` and `readme.md` would silently overwrite each other on disk even
    /// though the backend treats them as distinct files (#1040). Original casing is
    /// preserved in the returned paths.
    static func uniqueRelativePaths(_ paths: [String]) -> [String] {
        var used = Set<String>()
        return paths.map { path in
            var candidate = path
            var copyNumber = 2
            while used.contains(candidate.lowercased()) {
                candidate = copyPath(path, number: copyNumber)
                copyNumber += 1
            }
            used.insert(candidate.lowercased())
            return candidate
        }
    }

    private static func copyPath(_ path: String, number: Int) -> String {
        var components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let filename = components.popLast() else {
            return "untitled-\(number)"
        }

        let copy = copyFilename(filename, number: number)
        return (components + [copy]).joined(separator: "/")
    }

    private static func copyFilename(_ filename: String, number: Int) -> String {
        guard let dot = filename.lastIndex(of: "."),
              dot != filename.startIndex else {
            return "\(filename)-\(number)"
        }

        return "\(filename[..<dot])-\(number)\(filename[dot...])"
    }
}
