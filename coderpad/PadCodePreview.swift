//
//  PadCodePreview.swift
//  coderpad
//

import AppKit
import SwiftUI

/// One displayable file in an environment's code preview, carrying the
/// language used to highlight it (derived from the file's own extension, with
/// the environment language as a fallback).
struct CodeFile: Identifiable, Hashable {
    /// A stable identifier derived from the file's path (not its array position), so a
    /// reload that reorders or changes the environment's files doesn't silently remap
    /// which file a retained selection points at.
    let id: String
    let path: String?
    let contents: String
    let language: String?

    /// The file's name without its directory, for compact tab labels.
    var name: String {
        guard let path, !path.isEmpty else { return "untitled" }
        return path.split(separator: "/").last.map(String.init) ?? path
    }

    /// Strips CoderPad's `multifile_` prefix so the environment language can
    /// stand in for a file that has no recognised extension.
    private static func baseLanguage(_ language: String?) -> String? {
        guard let language else { return nil }
        let lowered = language.lowercased()
        if lowered.hasPrefix("multifile_") {
            return String(lowered.dropFirst("multifile_".count))
        }
        return language
    }

    /// Maps a file extension to the CoderPad language code the highlighter
    /// understands. A table rather than a `switch` so the lookup stays a single
    /// statement and aliases collapse onto one code without a giant branch.
    private static let languageByExtension: [String: String] = [
        "py": "python",
        "js": "javascript", "jsx": "javascript", "mjs": "javascript", "cjs": "javascript",
        "ts": "typescript", "tsx": "typescript",
        "swift": "swift", "go": "go", "rs": "rust", "java": "java",
        "kt": "kotlin", "kts": "kotlin",
        "scala": "scala", "sc": "scala", "rb": "ruby",
        "c": "c", "h": "c",
        "cpp": "cpp", "cc": "cpp", "cxx": "cpp", "hpp": "cpp", "hh": "cpp",
        "cs": "csharp", "m": "objective-c", "mm": "objective-c",
        "php": "php", "r": "r", "sql": "sql",
        "sh": "bash", "bash": "bash",
        "ex": "elixir", "exs": "elixir",
        "erl": "erlang", "hrl": "erlang", "hs": "haskell",
        "pl": "perl", "pm": "perl", "lua": "lua", "dart": "dart",
        "clj": "clojure", "cljs": "clojure", "cljc": "clojure",
        "ml": "ocaml", "mli": "ocaml", "fs": "fsharp", "fsx": "fsharp",
        "html": "html", "htm": "html", "css": "css",
        "txt": "plaintext", "md": "plaintext", "markdown": "plaintext"
    ]

    static func language(forPath path: String?, fallback: String?) -> String? {
        guard let path, let dot = path.lastIndex(of: "."), dot < path.index(before: path.endIndex) else {
            return baseLanguage(fallback)
        }
        let ext = path[path.index(after: dot)...].lowercased()
        return languageByExtension[ext] ?? baseLanguage(fallback)
    }
}

/// A code card for one environment. Single-file environments render exactly as
/// before — a single highlighted scroll. Multi-file environments gain a row of
/// file tabs and a per-file path header, so the files no longer run together
/// in one concatenated blob and each is highlighted in its own language.
struct EnvironmentCodeCard: View {
    let files: [CodeFile]
    let isActive: Bool
    /// Whether to flag the active environment. Only meaningful when a pad has
    /// several environments; with a single one the active flag says nothing.
    let showActiveBadge: Bool
    /// The environment-level language, shown as a chip (e.g. "Python Project").
    let language: String?
    let padID: String
    let dark: Bool

    /// The files arranged into a folder tree by their paths, folders before
    /// files and each group sorted by name. Built once in `init` rather than on
    /// every `body` pass so dragging the sidebar handle (which re-evaluates
    /// `body` each frame) doesn't re-run the recursive grouping and sorting.
    let fileTree: [FileTreeNode]

    init(
        files: [CodeFile],
        isActive: Bool,
        showActiveBadge: Bool,
        language: String?,
        padID: String,
        dark: Bool
    ) {
        self.files = files
        self.isActive = isActive
        self.showActiveBadge = showActiveBadge
        self.language = language
        self.padID = padID
        self.dark = dark
        fileTree = Self.makeFileTree(from: files)
    }

    @State var selectedFileID: String?
    /// Folder paths the user has collapsed. Absence means expanded, so every
    /// folder starts open and the whole project is visible by default.
    @State var collapsedFolders: Set<String> = []
    /// The persisted file sidebar width. The user can drag the divider to resize
    /// it (see `resizeHandle`); a wider sidebar reveals long file names that would
    /// otherwise truncate. Stored so the chosen width sticks across launches, and
    /// shared by every code card so they stay aligned. The panes only ever render
    /// at this width — a drag previews with a lightweight indicator and commits
    /// here on release (see `resizeHandle`), so no heavy relayout runs mid-drag.
    @AppStorage("padFileSidebarWidth") var storedWidth: Double = 180
    /// The previewed width while a resize drag is in progress, or `nil` when not
    /// dragging. Only a thin indicator line follows this; the actual sidebar keeps
    /// its committed `storedWidth` until the drag ends, so dragging never forces
    /// the code pane (a selectable, syntax-highlighted scroll view that is costly
    /// to re-lay-out) to reflow on every frame — the source of the stutter.
    @State var liveWidth: Double?
    /// On-device explanation of the selected file, shown in a popover. Keyed to
    /// the file it was generated for so switching files doesn't show a stale one.
    @State var explanation: String?
    @State var explanationFileID: String?
    @State var isExplaining = false
    @State var showExplanation = false

    var selected: CodeFile {
        files.first { $0.id == selectedFileID } ?? files[0]
    }

    var isMultiFile: Bool {
        files.count > 1
    }

    /// Builds the folder tree from a flat file list. Pure and static so it can run
    /// once at `init` time.
    private static func makeFileTree(from files: [CodeFile]) -> [FileTreeNode] {
        let entries = files.map { file -> (segments: [String], file: CodeFile) in
            let path = file.path ?? file.name
            let segments = path.split(separator: "/")
                .map(String.init)
                .filter { $0 != "." && $0 != ".." }
            return (segments.isEmpty ? [file.name] : segments, file)
        }
        return makeNodes(entries: entries, prefix: "")
    }

    private static func makeNodes(
        entries: [(segments: [String], file: CodeFile)],
        prefix: String
    ) -> [FileTreeNode] {
        var folderOrder: [String] = []
        var groups: [String: [(segments: [String], file: CodeFile)]] = [:]
        var leaves: [(name: String, file: CodeFile)] = []

        for entry in entries {
            if entry.segments.count <= 1 {
                leaves.append((entry.segments.first ?? entry.file.name, entry.file))
            } else {
                let head = entry.segments[0]
                if groups[head] == nil {
                    groups[head] = []
                    folderOrder.append(head)
                }
                groups[head]?.append((Array(entry.segments.dropFirst()), entry.file))
            }
        }

        var nodes: [FileTreeNode] = []
        for folder in folderOrder.sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }) {
            let childPrefix = prefix.isEmpty ? folder : prefix + "/" + folder
            let children = makeNodes(entries: groups[folder] ?? [], prefix: childPrefix)
            nodes.append(FileTreeNode(id: "folder:" + childPrefix, name: folder, file: nil, children: children))
        }
        for leaf in leaves.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) {
            nodes.append(FileTreeNode(id: "file:\(leaf.file.id)", name: leaf.name, file: leaf.file, children: []))
        }
        return nodes
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                header
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // When the environment's files change (added/removed/renamed — ids are
        // path-based), clear the retained selection so `selected` falls back to the
        // first file rather than pointing at a stale or wrong file. An in-place
        // contents update keeps the same ids, so the selection survives it.
        .onChange(of: files.map(\.id)) { _, _ in
            selectedFileID = nil
        }
    }

    /// Single-file environments render a lone highlighted scroll. Multi-file
    /// environments place a vertical file list beside the code so every file is
    /// visible at once, the way an IDE shows a project, instead of forcing a
    /// long sideways scroll through a row of tabs.
    private var content: some View {
        Group {
            if isMultiFile {
                HStack(alignment: .top, spacing: 0) {
                    fileSidebar
                    resizeHandle
                    codeScroll
                }
                // While dragging, a thin accent line previews where the divider
                // will land. The panes themselves don't move until release, so the
                // (expensive) code pane never reflows mid-drag.
                .overlay(alignment: .leading) {
                    if let liveWidth {
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: 2)
                            .frame(maxHeight: .infinity)
                            .offset(x: liveWidth)
                            .allowsHitTesting(false)
                    }
                }
            } else {
                codeScroll
            }
        }
        .background(Color.subtleStroke.opacity(0.5),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityLabel(accessibilityLabel)
    }
}

/// The scrollable, syntax-highlighted view of one file's source. Kept separate
/// and `Equatable` so SwiftUI skips re-running the costly highlighter when the
/// enclosing card re-renders for unrelated reasons — most importantly while the
/// user drags the file sidebar's resize handle, which would otherwise re-tokenize
/// the whole file on every frame and make the drag stutter. `body` (and thus the
/// highlight pass) runs again only when the contents, language, or appearance
/// differ from the previous value.
struct HighlightedCode: View, Equatable {
    let contents: String
    let language: String?
    let dark: Bool

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            Text(SyntaxHighlighter.highlight(contents, language: language, dark: dark))
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .defaultScrollAnchor(.topLeading)
        .frame(maxWidth: .infinity, maxHeight: 360, alignment: .topLeading)
    }
}

/// A node in the file tree built from the files' paths. A leaf carries a
/// `file`; a folder carries `children` and a nil `file`.
struct FileTreeNode: Identifiable {
    let id: String
    let name: String
    let file: CodeFile?
    let children: [FileTreeNode]

    var isFolder: Bool {
        file == nil
    }
}

/// Renders one level of the file tree, recursing into expanded folders. Pulled
/// out as its own view so the recursion stays straightforward and each row
/// indents by its depth.
struct FileTreeRows: View {
    let nodes: [FileTreeNode]
    let depth: Int
    let selectedID: String
    @Binding var collapsedFolders: Set<String>
    let onSelect: (String) -> Void

    var body: some View {
        ForEach(nodes) { node in
            if node.isFolder {
                folderRow(node)
                if !collapsedFolders.contains(node.id) {
                    FileTreeRows(
                        nodes: node.children,
                        depth: depth + 1,
                        selectedID: selectedID,
                        collapsedFolders: $collapsedFolders,
                        onSelect: onSelect
                    )
                }
            } else if let file = node.file {
                fileRow(node, file: file)
            }
        }
    }

    private func folderRow(_ node: FileTreeNode) -> some View {
        let collapsed = collapsedFolders.contains(node.id)
        return Button {
            if collapsed {
                collapsedFolders.remove(node.id)
            } else {
                collapsedFolders.insert(node.id)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 10)
                Image(systemName: "folder")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(node.name)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 5)
            .padding(.trailing, 8)
            .padding(.leading, CGFloat(depth) * 12 + 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func fileRow(_: FileTreeNode, file: CodeFile) -> some View {
        let isSelected = file.id == selectedID
        return Button {
            onSelect(file.id)
        } label: {
            HStack(spacing: 5) {
                // Align the file's icon with the folder's name column by
                // reserving the same width the disclosure chevron takes.
                Color.clear.frame(width: 10)
                Image(systemName: "doc")
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                Text(file.name)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 5)
            .padding(.trailing, 8)
            .padding(.leading, CGFloat(depth) * 12 + 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? Color.accentColor.opacity(0.18) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(file.path ?? file.name)
    }
}
