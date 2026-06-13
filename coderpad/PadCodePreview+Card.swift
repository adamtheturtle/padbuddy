//
//  PadCodePreview+Card.swift
//  coderpad
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension EnvironmentCodeCard {
    var header: some View {
        HStack {
            SectionHeader(title: "Code", systemImage: "chevron.left.slash.chevron.right")
            // When several environments are stacked, flag the active one so the
            // cards don't blur together. The language chip below names each.
            if showActiveBadge, isActive {
                Chip(text: "Active", systemImage: "checkmark.seal", tint: .green)
            }
            Spacer()
            if let language, !language.isEmpty {
                Chip(text: language.languageDisplayName)
            }
            // The per-file actions live in the header rather than floating over
            // the code so they never overlap the source. The environment-level
            // "Download Zip" trails them, reading as "save the whole project"
            // rather than being tied to the one visible file.
            if PadCodeExplainer.isAvailable {
                explainButton
            }
            downloadButton
            copyButton
            if isMultiFile {
                downloadAllButton
            }
        }
    }

    /// Header button that saves every file in a multi-file environment as one
    /// zip. Kept out of the per-file code pane so it doesn't read as acting on
    /// the single file currently shown.
    private var downloadAllButton: some View {
        Button {
            downloadAll(files)
        } label: {
            Label("Download Zip", systemImage: "arrow.down.circle")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .help("Download all files as a zip")
        .accessibilityLabel("Download all files as a zip")
    }

    /// Header button that copies the selected file's contents.
    private var copyButton: some View {
        Button {
            copy(selected.contents)
        } label: {
            Image(systemName: "doc.on.doc")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .help("Copy code")
        .accessibilityLabel("Copy code")
    }

    /// Header button that saves the file currently shown to disk via a save
    /// panel, pre-filled with its name so its extension carries over. It acts on
    /// the visible file only; the whole environment is downloaded via the
    /// header's "Download Zip" button. The help text names the file in a
    /// multi-file project so it doesn't read as a download-all.
    private var downloadButton: some View {
        Button {
            download(selected)
        } label: {
            Image(systemName: "square.and.arrow.down")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .help(isMultiFile ? "Download \(selected.name)" : "Download code")
        .accessibilityLabel(isMultiFile ? "Download \(selected.name)" : "Download code")
    }

    /// A vertical list of the environment's files, pinned beside the code. It
    /// scrolls independently so even a project with many files stays browsable
    /// without the code pane having to grow.
    var fileSidebar: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 2) {
                FileTreeRows(
                    nodes: fileTree,
                    depth: 0,
                    selectedID: selected.id,
                    collapsedFolders: $collapsedFolders,
                    onSelect: { selectedFileID = $0 }
                )
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: CGFloat(storedWidth))
    }

    /// The draggable divider between the file list and the code. It draws the
    /// same hairline as a plain `Divider` but carries a wider, invisible hit
    /// target so the resize is easy to grab, and shows the left/right resize
    /// cursor on hover. Dragging only moves a preview line (`liveWidth`); the new
    /// width is committed to `storedWidth` on release so the panes relayout once,
    /// not on every frame.
    var resizeHandle: some View {
        Divider()
            .overlay {
                Color.clear
                    .frame(width: 10)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                // Measure each drag from the committed width and
                                // move only the lightweight preview indicator —
                                // the heavy panes stay put until release.
                                let next = storedWidth + Double(value.translation.width)
                                liveWidth = min(max(120, next), 420)
                            }
                            .onEnded { _ in
                                // Commit the previewed width (one relayout) and
                                // clear the preview.
                                if let liveWidth { storedWidth = liveWidth }
                                liveWidth = nil
                            }
                    )
            }
    }

    var codeScroll: some View {
        // The highlighted code lives in its own `Equatable` view so resizing the
        // sidebar — which re-evaluates this card's `body` every drag frame —
        // doesn't re-run the (expensive) syntax highlighter. It only recomputes
        // when the file contents, language, or appearance actually change.
        HighlightedCode(contents: selected.contents, language: selected.language, dark: dark)
            .equatable()
    }

    /// Header button that explains the selected file on device. The result opens
    /// in a popover anchored to the button. Mirrors the privacy posture of the
    /// rest of the AI features: nothing leaves the Mac and nothing runs until the
    /// user taps. Disabled while a generation is in flight.
    private var explainButton: some View {
        Button {
            Task { await explainSelected() }
        } label: {
            if isExplaining {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "sparkles")
            }
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .disabled(isExplaining)
        .help("Explain this file")
        .accessibilityLabel("Explain this file")
        .popover(isPresented: $showExplanation, arrowEdge: .bottom) {
            explanationPopover
        }
    }

    private var explanationPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Explanation", systemImage: "sparkles")
                .font(.headline)
            ScrollView {
                Text(explanation ?? "")
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(width: 320, height: 220)
    }

    /// Generates (or reuses) an on-device explanation of the visible file, then
    /// shows it in the popover. Reuses an explanation already generated for the
    /// same file so reopening the popover is instant and doesn't re-run the model.
    private func explainSelected() async {
        if explanationFileID == selected.id, explanation != nil {
            showExplanation = true
            return
        }
        isExplaining = true
        defer { isExplaining = false }
        if let result = await PadCodeExplainer.explain(file: selected) {
            explanation = result
            explanationFileID = selected.id
            showExplanation = true
        }
    }

    var accessibilityLabel: String {
        // Name the environment by its language, the same identity shown visually.
        let environmentName = language.flatMap { $0.isEmpty ? nil : $0.languageDisplayName }
        if isMultiFile {
            return "Code preview of \(selected.name)\(environmentName.map { " in \($0)" } ?? "") in pad \(padID)"
        }
        return environmentName.map { "Code preview of \($0) in pad \(padID)" }
            ?? "Code preview of pad \(padID)"
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Writes the file's contents to a user-chosen location. The save panel
    /// grants the sandboxed app write access to the picked URL, so no extra
    /// entitlement beyond user-selected read-write is needed.
    private func download(_ file: CodeFile) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = file.name
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? file.contents.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Saves every file in the environment as a single zip, chosen via a save
    /// panel pre-filled with the pad id. The archive keeps each file's relative
    /// folder path so a multi-file project unzips back into its original layout.
    private func downloadAll(_ files: [CodeFile]) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "pad-\(padID).zip"
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        try? writeZip(of: files, to: destination)
    }

    /// Stages the files into a temporary folder (named so the archive's root
    /// reads as `pad-<id>`), then uses `NSFileCoordinator`'s `.forUploading`
    /// option to produce a zip of that folder and copies it to `destination`.
    /// This avoids pulling in a third-party archiving dependency.
    private func writeZip(of files: [CodeFile], to destination: URL) throws {
        let fileManager = FileManager.default
        let container = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let root = container.appendingPathComponent("pad-\(padID)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: container) }

        for file in files {
            // Keep the file's relative path, dropping any `.`/`..` segments so a
            // crafted path can't escape the staging folder.
            let relative = (file.path ?? file.name)
                .split(separator: "/")
                .filter { $0 != "." && $0 != ".." }
                .joined(separator: "/")
            let fileURL = root.appendingPathComponent(relative.isEmpty ? file.name : relative)
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
            try file.contents.write(to: fileURL, atomically: true, encoding: .utf8)
        }

        var coordinatorError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(
            readingItemAt: root,
            options: .forUploading,
            error: &coordinatorError
        ) { zippedURL in
            do {
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.copyItem(at: zippedURL, to: destination)
            } catch {
                copyError = error
            }
        }
        if let coordinatorError { throw coordinatorError }
        if let copyError { throw copyError }
    }
}
