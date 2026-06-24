//
//  PadCodePreview.swift
//  coderpad
//

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

    /// An empty stand-in so `EnvironmentCodeCard.selected` stays total without a
    /// force-subscript. Callers already guard against rendering the card with no files
    /// (#419), so this is purely a defensive fallback and never actually displayed.
    static let placeholder = Self(id: "", path: nil, contents: "", language: nil)
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
    /// When the environment was seeded from one of CoderPad's built-in examples,
    /// its identifier (e.g. "examples/035-django-shopping-list"). `nil` for a custom
    /// or question-backed environment. Surfaced as a "From example" attribution.
    let exampleQuestionID: String?
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
        dark: Bool,
        exampleQuestionID: String? = nil
    ) {
        self.files = files
        self.isActive = isActive
        self.showActiveBadge = showActiveBadge
        self.language = language
        self.exampleQuestionID = exampleQuestionID
        self.padID = padID
        self.dark = dark
        fileTree = Self.makeFileTree(from: files)
    }

    /// A humanized name for a built-in example identifier, or `nil` when the
    /// environment isn't from an example. Strips the `examples/` prefix and any
    /// leading `NNN-` ordinal, then turns dashes into spaces (e.g.
    /// "examples/035-django-shopping-list" → "Django shopping list").
    var exampleAttribution: String? {
        guard let raw = exampleQuestionID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }

        var slug = raw
        if let slash = slug.lastIndex(of: "/") { slug = String(slug[slug.index(after: slash)...]) }
        // Drop a leading ordinal like "035-".
        if let dash = slug.firstIndex(of: "-"),
           slug[slug.startIndex ..< dash].allSatisfy(\.isNumber), slug.startIndex != dash {
            slug = String(slug[slug.index(after: dash)...])
        }
        let words = slug.replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !words.isEmpty else { return nil }

        return words.prefix(1).uppercased() + words.dropFirst()
    }

    @State var selectedFileID: String?
    // SwiftUI @State read only via its $-projected binding.
    // periphery:ignore
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
    @State var explanation: CodeExplanation?
    @State var explanationFileID: String?
    @State var isExplaining = false
    @State var showExplanation = false

    var selected: CodeFile {
        files.first { $0.id == selectedFileID } ?? files.first ?? .placeholder
    }

    var isMultiFile: Bool {
        files.count > 1
    }

    /// Builds the folder tree from a flat file list. Pure and static so it can run
    /// once at `init` time.
    private static func makeFileTree(from files: [CodeFile]) -> [FileTreeNode] {
        // Explicitly-typed intermediates keep the tuple-returning map cheap to
        // type-check; the inferred chain otherwise blows the 250ms budget on CI's
        // slower toolchain (#427).
        let entries: [(segments: [String], file: CodeFile)] = files.map { file in
            let path = file.path ?? file.name
            let segments: [String] = path.split(separator: "/")
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
                if let exampleAttribution {
                    MetaLabel(text: String(localized: "From example: \(exampleAttribution)"),
                              systemImage: "shippingbox")
                }
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
            // Also drop any open code explanation: it was generated for a file id
            // that may no longer exist, and `selected` now falls back to the first
            // file — leaving it up would show file A's analysis over a different file.
            showExplanation = false
            explanation = nil
            explanationFileID = nil
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

    /// The highlighted result, filled in by an off-main pass; plain `contents`
    /// renders until it lands so the main thread isn't blocked tokenizing (#372).
    @State private var highlighted: AttributedString?

    /// Compare only the inputs (not the @State result) so SwiftUI keeps skipping
    /// re-renders for unrelated reasons, e.g. the file sidebar's resize drag.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.contents == rhs.contents && lhs.language == rhs.language && lhs.dark == rhs.dark
    }

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            Text(highlighted ?? AttributedString(contents))
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .defaultScrollAnchor(.topLeading)
        // A *determinate* height, not `maxHeight: 360`. This scroll is vertical and
        // lives inside the detail pane's own vertical scroll; a flexible `maxHeight`
        // range made the outer scroll re-measure this view's full (un-clamped) content
        // height on every layout probe to decide where in 0...360 it should land —
        // re-running CoreText text measurement combinatorially and beachballing the
        // main thread (#494). Pinning the height gives the nested scroll an unambiguous
        // size, so the outer scroll never renegotiates it; the code still scrolls in
        // both axes within this fixed viewport.
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 360)
        // Re-run only when the inputs change; a same-id task isn't restarted, so
        // an unrelated re-render won't re-highlight.
        .task(id: HighlightInput(contents: contents, language: language, dark: dark)) {
            highlighted = await SyntaxHighlighter.highlight(contents, language: language, dark: dark)
        }
    }
}

/// The inputs that determine a highlight pass, so `HighlightedCode`'s `.task`
/// restarts exactly when one of them changes.
private struct HighlightInput: Equatable {
    let contents: String
    let language: String?
    let dark: Bool
}

/// A node in the file tree built from the files' paths. A leaf carries a
/// `file`; a folder carries `children` and a nil `file`.
struct FileTreeNode: Identifiable {
    let id: String
    let name: String
    let file: CodeFile?
    let children: [Self]

    var isFolder: Bool {
        file == nil
    }
}
