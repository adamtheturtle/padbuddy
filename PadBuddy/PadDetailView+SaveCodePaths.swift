//
//  PadDetailView+SaveCodePaths.swift
//  coderpad
//

import Foundation

extension PadDetailView {
    /// Replaces characters that are unsafe in a single path component, so a pad
    /// title or file name can't break out of its folder or confuse the shell.
    static func sanitizeComponent(_ name: String) -> String {
        SaveCodePathHelpers.sanitizeComponent(name)
    }

    static func uniqueRelativePaths(_ paths: [String]) -> [String] {
        SaveCodePathHelpers.uniqueRelativePaths(paths)
    }

    /// Whether `env` would produce any display files at all, without building them
    /// (#2095). Deliberately mirrors `displayFiles(for:)`'s skip condition below —
    /// that is the only thing deciding emptiness, since every file with contents
    /// yields exactly one entry.
    static func hasDisplayableFiles(in env: PadEnvironment) -> Bool {
        env.fileContents.contains { $0.binary == true || !($0.contents ?? "").isEmpty }
    }

    /// The non-empty files of an environment, each paired with a language
    /// inferred from its own extension. A multi-file project (e.g. a Django
    /// app) mixes `.py`, `.html`, and `.css`; deriving the language per file
    /// lets each be highlighted correctly instead of forcing the environment's
    /// single language onto all of them.
    func displayFiles(for env: PadEnvironment) -> [CodeFile] {
        displayFilesByEnvironment[env.id] ?? Self.computeDisplayFiles(for: env)
    }

    /// Every environment's display files, keyed by id, for `displayFilesByEnvironment`.
    static func normalizedDisplayFiles(for environments: [PadEnvironment]) -> [Int: [CodeFile]] {
        var result: [Int: [CodeFile]] = [:]
        for env in environments {
            result[env.id] = computeDisplayFiles(for: env)
        }
        return result
    }

    /// The normalization itself. Callers go through `displayFiles(for:)`, which
    /// reads the cached result rather than repeating this per render (#2089).
    static func computeDisplayFiles(for env: PadEnvironment) -> [CodeFile] {
        var occurrences: [String: Int] = [:]
        var result: [CodeFile] = []
        for (index, file) in env.fileContents.enumerated() {
            let isBinary = file.binary == true
            guard isBinary || file.contents?.isEmpty == false else { continue }

            let body = file.contents ?? ""

            // Canonicalize the server-supplied path once — dropping empty, ".",
            // and ".." segments — and derive the id, tree, and export layout from
            // the same canonical form, so "a/../b.swift" and "a/b.swift" can't
            // carry different ids into colliding destinations (#1173).
            let canonicalPath: String? = Self.canonicalCodePath(file.path)
            let base: String = canonicalPath ?? "idx-\(index)"
            // Duplicate paths get an occurrence suffix so two files at one path
            // keep distinct list/selection identities instead of sharing rows,
            // selection, and explanations (#1172).
            let occurrence: Int = occurrences[base, default: 0]
            occurrences[base] = occurrence + 1
            result.append(CodeFile(
                id: occurrence == 0 ? base : "\(base)#\(occurrence + 1)",
                path: canonicalPath ?? file.path,
                contents: body,
                language: CodeFile.language(forPath: file.path, fallback: env.language),
                isBinary: isBinary
            ))
        }
        return result
    }

    /// Maps each known language code to a file extension. A table rather than a
    /// `switch` so the lookup stays a single statement and several aliases can map
    /// to the same extension without one giant branch.
    static let extensionByLanguage: [String: String] = [
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
        "ocaml": "ml", "f#": "fs", "fsharp": "fs",
        // Markdown is in the supported-language table; a legacy pathless
        // Markdown pad must export as .md, not .txt (#1744).
        "markdown": "md", "md": "md"
    ]

    /// A reasonable file extension for code that has no path of its own (a
    /// legacy single-file pad), derived from its language. Trimmed before lookup:
    /// an API value like "python3 " must not fall through to .txt (#1743).
    static func fileExtension(forLanguage language: String?) -> String {
        var lowered = (language ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lowered.hasPrefix("multifile_") {
            lowered = String(lowered.dropFirst("multifile_".count))
        }
        return extensionByLanguage[lowered] ?? "txt"
    }

    /// The path with empty, ".", and ".." segments dropped, or nil when nothing
    /// usable remains (#1173).
    private static func canonicalCodePath(_ path: String?) -> String? {
        guard let path else { return nil }

        let segments: [String] = path.split(separator: "/")
            .map(String.init)
            .filter { $0 != "." && $0 != ".." }
        return segments.isEmpty ? nil : segments.joined(separator: "/")
    }
}

/// Shared by the pad "Save All Code"/zip export (via `PadDetailView.uniqueRelativePaths`)
/// and the per-environment folder download (via `CodeExportPathPlan`). `nonisolated` so
/// the iOS `FileDocument` export path can call it off the main actor.
nonisolated enum SaveCodePathHelpers {
    /// Replaces characters that are unsafe in a single path component (including
    /// the colon, which Finder still treats as a separator) and control
    /// characters, so a remotely supplied name can't break out of its folder,
    /// fail the exporter, or behave differently between macOS and iOS (#1177).
    /// Characters unsafe in a single path component. Built once: `CharacterSet`
    /// unions are not cheap, and this runs per path component, file, and environment
    /// label on every save or export (#2218).
    private static let invalidPathCharacters = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        .union(.controlCharacters).union(.newlines)

    /// APFS / HFS+ / most POSIX volumes reject a single path component above this
    /// many UTF-8 bytes (`NAME_MAX`). Remote pad titles and collision suffixes can
    /// otherwise make Save All Code fail mid-write (#4667).
    static let maximumComponentUTF8Bytes = 255

    static func sanitizeComponent(_ name: String) -> String {
        let cleaned = name.components(separatedBy: Self.invalidPathCharacters).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !cleaned.allSatisfy({ $0 == "." }) else {
            return "untitled"
        }

        return boundedComponent(cleaned)
    }

    /// Keeps `name` within `maximumComponentUTF8Bytes`, preferring to shorten the
    /// stem so a trailing extension stays intact for uniqueness and type hints.
    static func boundedComponent(_ name: String, reservingUTF8Bytes reserved: Int = 0) -> String {
        let budget = maximumComponentUTF8Bytes - max(0, reserved)
        guard budget > 0 else { return "untitled" }
        guard name.utf8.count > budget else { return name }

        if let dot = name.lastIndex(of: "."), dot != name.startIndex {
            let ext = String(name[dot...])
            let stem = String(name[..<dot])
            let extBytes = ext.utf8.count
            if extBytes < budget {
                let truncatedStem = utf8Prefix(stem, maximumBytes: budget - extBytes)
                if !truncatedStem.isEmpty {
                    return truncatedStem + ext
                }
            }
        }

        let truncated = utf8Prefix(name, maximumBytes: budget)
        return truncated.isEmpty ? "untitled" : truncated
    }

    private static func utf8Prefix(_ string: String, maximumBytes: Int) -> String {
        guard string.utf8.count > maximumBytes else { return string }

        let prefix = string.utf8.prefix(maximumBytes)
        if let exact = String(prefix) {
            return exact
        }
        for dropped in 1 ... min(3, maximumBytes) {
            if let valid = String(string.utf8.prefix(maximumBytes - dropped)) {
                return valid
            }
        }
        return ""
    }

    /// Renames collisions so every returned path is unique. Uniqueness is judged
    /// case-insensitively and Unicode-normalized: macOS/iOS volumes are
    /// case-insensitive by default and treat canonically equivalent names as one
    /// path, so `README.md`/`readme.md` — or an NFC and NFD spelling of the same
    /// accented name — would silently overwrite each other on disk even though
    /// the backend treats them as distinct files (#1040, #1174). A file whose path
    /// is also another file's directory prefix (`src` next to `src/main.swift`) is
    /// renamed too: writing one as a file makes creating the other's directory
    /// fail and aborts the export mid-write (#1739). Original casing and
    /// composition are preserved in the returned paths.
    static func uniqueRelativePaths(_ paths: [String]) -> [String] {
        func key(_ path: String) -> String {
            path.precomposedStringWithCanonicalMapping.lowercased()
        }

        // Every directory prefix any path needs; no file may claim one (#1739).
        var directories = Set<String>()
        for path in paths {
            var components = path.split(separator: "/").map(String.init)
            components.removeLast()
            while !components.isEmpty {
                directories.insert(key(components.joined(separator: "/")))
                components.removeLast()
            }
        }

        var used = Set<String>()
        return paths.map { path in
            var candidate = path
            var copyNumber = 2
            while used.contains(key(candidate)) || directories.contains(key(candidate)) {
                candidate = copyPath(path, number: copyNumber)
                copyNumber += 1
            }
            used.insert(key(candidate))
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
        let suffix = "-\(number)"
        let suffixBytes = suffix.utf8.count
        guard let dot = filename.lastIndex(of: "."),
              dot != filename.startIndex else {
            // Reserve room for the collision suffix before truncating (#4667).
            return boundedComponent(filename, reservingUTF8Bytes: suffixBytes) + suffix
        }

        let stem = String(filename[..<dot])
        let ext = String(filename[dot...])
        let reserved = suffixBytes + ext.utf8.count
        return boundedComponent(stem, reservingUTF8Bytes: reserved) + suffix + ext
    }
}
