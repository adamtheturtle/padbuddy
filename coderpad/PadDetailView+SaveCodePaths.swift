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

private enum SaveCodePathHelpers {
    static func uniqueRelativePaths(_ paths: [String]) -> [String] {
        var used = Set<String>()
        return paths.map { path in
            var candidate = path
            var copyNumber = 2
            while used.contains(candidate) {
                candidate = copyPath(path, number: copyNumber)
                copyNumber += 1
            }
            used.insert(candidate)
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
