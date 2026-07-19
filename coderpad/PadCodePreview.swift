//
//  PadCodePreview.swift
//  coderpad
//

import SwiftUI
#if os(iOS)
    import UniformTypeIdentifiers
#endif

/// One displayable file in an environment's code preview, carrying the
/// language used to highlight it (derived from the file's own extension, with
/// the environment language as a fallback).
nonisolated struct CodeFile: Identifiable, Hashable {
    /// A stable identifier derived from the file's path (not its array position), so a
    /// reload that reorders or changes the environment's files doesn't silently remap
    /// which file a retained selection points at.
    let id: String
    let path: String?
    let contents: String
    let language: String?
    /// The contents hashed once, when the file is built. `explanationKey` is read
    /// for every file inside the code card's `onChange`, which re-evaluates on each
    /// body pass, so hashing there re-hashed every file in the environment whenever
    /// the card changed state — selecting a file, opening the explanation popover,
    /// or going full-screen (#2099).
    let contentsHash: Int

    init(id: String, path: String?, contents: String, language: String?) {
        self.id = id
        self.path = path
        self.contents = contents
        self.language = language
        contentsHash = contents.hashValue
    }

    /// The file's name without its directory, for compact tab labels.
    var name: String {
        guard let path, !path.isEmpty else { return "untitled" }

        // Slice from the last separator rather than splitting: the full split
        // allocated an array of every path segment to keep one of them, on a property
        // read while rendering the file tabs (#2455).
        guard let slash = path.lastIndex(of: "/") else { return path }

        let component = path[path.index(after: slash)...]
        return component.isEmpty ? path : String(component)
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
        "c": "c",
        "cpp": "cpp", "cc": "cpp", "cxx": "cpp", "hpp": "cpp", "hh": "cpp",
        "cs": "csharp", "mm": "objective-c",
        "php": "php", "r": "r", "sql": "sql",
        "sh": "bash", "bash": "bash",
        "ex": "elixir", "exs": "elixir",
        "erl": "erlang", "hrl": "erlang", "hs": "haskell",
        "pl": "perl", "pm": "perl", "lua": "lua", "dart": "dart",
        "clj": "clojure", "cljs": "clojure", "cljc": "clojure",
        "ml": "ocaml", "mli": "ocaml", "fs": "fsharp", "fsx": "fsharp",
        "html": "html", "htm": "html", "css": "css",
        "json": "json", "yaml": "yaml", "yml": "yaml", "toml": "toml",
        "vue": "xml", "svelte": "xml", "gradle": "groovy",
        "txt": "plaintext", "md": "plaintext", "markdown": "plaintext"
    ]

    static func language(forPath path: String?, fallback: String?) -> String? {
        guard let path else { return baseLanguage(fallback) }

        // Dockerfiles conventionally have no extension. Match the final path
        // component so nested and case-varied project files highlight correctly.
        if path.split(separator: "/").last?.lowercased() == "dockerfile" {
            return "dockerfile"
        }

        guard let dot = path.lastIndex(of: "."), dot < path.index(before: path.endIndex) else {
            return baseLanguage(fallback)
        }

        let ext = path[path.index(after: dot)...].lowercased()
        let base = baseLanguage(fallback)
        // Objective-C and MATLAB share `.m`; the environment is the only
        // available disambiguator for a standalone source file (#1908).
        if ext == "m" {
            return base?.lowercased() == "matlab" ? "matlab" : "objective-c"
        }
        // C and C++ conventionally share `.h`; preserve the environment's C++
        // context instead of forcing every header through the C grammar (#1909).
        if ext == "h" {
            return base?.lowercased() == "cpp" ? "cpp" : "c"
        }
        return languageByExtension[ext] ?? base
    }

    /// An empty stand-in so `EnvironmentCodeCard.selected` stays total without a
    /// force-subscript. Callers already guard against rendering the card with no files
    /// (#419), so this is purely a defensive fallback and never actually displayed.
    static let placeholder = Self(id: "", path: nil, contents: "", language: nil)

    var explanationKey: CodeFileExplanationKey {
        CodeFileExplanationKey(id: id, contentsHash: contentsHash, language: language)
    }
}

nonisolated struct CodeFileExplanationKey: Hashable {
    let id: String
    /// Taken from ``CodeFile/contentsHash`` rather than hashed here, so building a
    /// key never walks the file's contents (#2099).
    let contentsHash: Int
    let language: String?
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

    /// The files keyed by id, so `selected` resolves with a dictionary lookup
    /// rather than a linear scan. `selected` is read several times per `body`
    /// pass (the code scroll, the accessibility label, and the download and
    /// explain actions), so the scan repeated on every render of a multi-file
    /// card; building the index once in `init` mirrors `fileTree` (#2103).
    private let filesByID: [String: CodeFile]

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
        fileTree = FileTreeMemo.tree(for: files)
        // Duplicate ids shouldn't happen (they're path-derived), but keep the
        // first one so the lookup matches the scan's "first match wins".
        filesByID = Dictionary(files.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
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
        // One pass rather than two `replacingOccurrences` walks plus a trim, each of
        // which rebuilt the whole string on a property read during render (#2456).
        let words = String(slug.map { $0 == "-" || $0 == "_" ? " " : $0 })
            .trimmingCharacters(in: .whitespaces)
        guard !words.isEmpty else { return nil }

        return words.prefix(1).uppercased() + words.dropFirst()
    }

    /// A cheap, order-independent stand-in for "which files are these". Reordering
    /// the same response must preserve the reader's selected file (#1885).
    private var fileIdentitySignature: Set<String> {
        CodeFileIdentity.signature(files)
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
    var sidebarWidth: Double {
        CodeSidebarWidth.clamped(storedWidth)
    }

    /// The previewed width while a resize drag is in progress, or `nil` when not
    /// dragging. Only a thin indicator line follows this; the actual sidebar keeps
    /// its committed `storedWidth` until the drag ends, so dragging never forces
    /// the code pane (a selectable, syntax-highlighted scroll view that is costly
    /// to re-lay-out) to reflow on every frame — the source of the stutter.
    @State var liveWidth: Double?
    /// On-device explanation of the selected file, shown in a popover. Keyed to
    /// the file revision it was generated for - id, contents, and language - so a
    /// refresh that rewrites the code at the same path regenerates instead of
    /// reusing stale analysis (#789, #937).
    @State var explanations: [CodeFileExplanationKey: CodeExplanation] = [:]
    @State var explanationLRU: [CodeFileExplanationKey] = []
    /// True when the last explanation attempt produced nothing, so the popover can
    /// say so and offer a retry instead of the button looking inert (#790).
    @State var explanationFailed = false
    @State var isExplaining = false
    @State var showExplanation = false
    /// Retained so leaving/replacing this card cancels model work (#1900).
    @State var explanationTask: Task<Void, Never>?
    @State var explanationGeneration = UUID()
    /// A failed code download/export to report (#791); non-nil presents an alert.
    @State var exportError: String?
    /// Presents the code in a large, full-screen viewer so the source can be read
    /// without the card's fixed 360-tall viewport. Tap/click the expand button to
    /// open it; the file list and selection carry over.
    @State var showFullCode = false
    #if os(iOS)
        /// The staged card export: `PadExportDocument` (shared with Save All Code),
        /// so a multi-file environment exports as a single zip rather than a
        /// directory FileWrapper - SwiftUI's exporter writes a directory document
        /// to a same-named temporary path and throws when a prior export of the
        /// same pad lingers there (#706).
        @State var exportDocument: PadExportDocument?
        @State var showCodeExporter = false
        @Environment(\.horizontalSizeClass) var horizontalSizeClass
    #endif

    var selected: CodeFile {
        if let selectedFileID, let file = filesByID[selectedFileID] { return file }

        return files.first ?? .placeholder
    }

    var isMultiFile: Bool {
        files.count > 1
    }

    // `makeFileTree`/`makeNodes` (and the `FileTreeMemo` that caches their output)
    // live in PadCodePreview+FileTree.swift to keep this file within the length lint.

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
        .sheet(isPresented: $showFullCode) {
            fullCodeViewer
        }
        #if os(iOS)
        .fileExporter(
            isPresented: $showCodeExporter,
            document: exportDocument,
            contentType: exportDocument?.contentType ?? .plainText,
            defaultFilename: exportDocument?.defaultName
        ) { result in
            exportDocument = nil
            // Surface a failed write instead of dismissing silently (#706).
            if case let .failure(error) = result {
                exportError = error.localizedDescription
            }
        }
        #endif
        .onAppear {
            // Render through the safe value immediately, then repair stale or
            // externally edited persisted state for every later card (#1888).
            storedWidth = sidebarWidth
        }
        .onDisappear(perform: cancelExplanation)
        // When the environment's files change (added/removed/renamed — ids are
        // path-based), clear the retained selection so `selected` falls back to the
        // first file rather than pointing at a stale or wrong file. An in-place
        // contents update keeps the same ids, so the selection survives it.
        .onChange(of: fileIdentitySignature) { _, _ in
            selectedFileID = nil
            // Also drop any open code explanation: it was generated for a file id
            // that may no longer exist, and `selected` now falls back to the first
            // file — leaving it up would show file A's analysis over a different file.
            clearExplanation()
            // And dismiss the full-screen viewer: left up, it would momentarily
            // render the replacement environment's first file under the old
            // title/selection with another project's collapsed folders (#1180).
            showFullCode = false
            collapsedFolders = []
        }
        // A refresh can change a file's contents or language without changing its
        // path-derived id. Keep the selected file, but discard any explanation for
        // the previous revision so the next Explain action regenerates (#937).
        .onChange(of: files.map(\.explanationKey)) { _, _ in
            clearExplanation()
        }
        .alert(
            "Couldn't save the code",
            isPresented: .init(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
    }

    private func clearExplanation() {
        cancelExplanation()
        showExplanation = false
        explanationFailed = false
        pruneExplanations()
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
                    in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .accessibilityLabel(accessibilityLabel)
    }
}

// `FileTreeNode` and `FileTreeMemo` live in PadCodePreview+FileTree.swift.
