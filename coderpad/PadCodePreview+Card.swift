//
//  PadCodePreview+Card.swift
//  coderpad
//

#if os(macOS)
    import AppKit
#endif
import SwiftUI
import UniformTypeIdentifiers

extension EnvironmentCodeCard {
    @ViewBuilder
    var header: some View {
        if isCompactPhone {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    codeTitle
                    if showActiveBadge, isActive {
                        activeChip
                    }
                    Spacer()
                    headerActions
                }
                if let language, !language.isEmpty {
                    MetaLabel(text: language.coderPadLanguageDisplayName)
                }
            }
        } else {
            HStack {
                codeTitle
                if showActiveBadge, isActive {
                    activeChip
                }
                // The language is informational, so it sits with the title and badge
                // on the left rather than among the action buttons — otherwise the
                // gray label reads as a fourth tappable control next to them.
                if let language, !language.isEmpty {
                    MetaLabel(text: language.coderPadLanguageDisplayName)
                }
                Spacer()
                headerActions
            }
        }
    }

    private var codeTitle: some View {
        // Keep the title on one line: on iPad the trailing action buttons can
        // claim the whole row, and without this SwiftUI compresses the header
        // label to a one-character-wide column that reads as vertical text.
        SectionHeader(title: "Code", systemImage: "chevron.left.slash.chevron.right")
            .fixedSize()
    }

    private var activeChip: some View {
        // When several environments are stacked, flag the active one so the
        // cards don't blur together — the one state here that genuinely needs
        // to pop, so it keeps the green capsule (matching an active pad's
        // StateBadge). The language label below names each.
        Chip(text: String(localized: "Active"), systemImage: "checkmark.seal", tint: .green)
    }

    private var headerActions: some View {
        HStack(spacing: isCompactPhone ? 2 : 8) {
            // These per-file actions live in the header rather than over the code.
            // Copy is the exception: it's overlaid inside the code block (top-right,
            // hover-revealed) since that's the conventional place users look for it.
            if PadCodeExplainer.isAvailable {
                explainButton
            }
            expandButton
            downloadButton
        }
    }

    private var isCompactPhone: Bool {
        #if os(iOS)
            horizontalSizeClass == .compact
        #else
            false
        #endif
    }

    /// Header button that opens the code in a large, full-screen viewer. The
    /// inline card pins the code to a 360-tall viewport (a deliberate fix for the
    /// nested-scroll hang, #494); this gives a way to read a long file in full
    /// without that clamp — a click on macOS, a tap on iPad.
    private var expandButton: some View {
        Button {
            showFullCode = true
        } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        // Compact icon-only header buttons are a tap on iPad; give each the 44pt touch
        // floor (no-op on macOS, #597) and a pointer hover highlight (#586).
        .touchTarget()
        .pointerHoverEffect()
        .help("View code full screen")
        .accessibilityLabel("View code full screen")
    }

    /// Header button that saves the environment to disk via a save panel. A
    /// multi-file project is downloaded as a folder (keeping each file's relative
    /// path); a single-file environment saves that one file, pre-filled with its
    /// name so its extension carries over.
    private var downloadButton: some View {
        Button {
            #if os(macOS)
                if isMultiFile {
                    downloadAll(files)
                } else {
                    download(selected)
                }
            #else
                if isMultiFile {
                    // Zip via the shared Save All Code document rather than exporting
                    // a directory FileWrapper, which fails on a repeated same-name
                    // export; a failed archive build is reported, not silent (#706).
                    if let archive = PadExportDocument(
                        zipName: "pad-\(padID)",
                        files: files.map { (path: $0.path ?? $0.name, contents: $0.contents) }
                    ) {
                        exportDocument = archive
                        showCodeExporter = true
                    } else {
                        exportError = String(localized: "Couldn't prepare the code archive to save.")
                    }
                } else {
                    exportDocument = PadExportDocument(
                        text: selected.contents,
                        contentType: .plainText,
                        defaultName: selected.name
                    )
                    showCodeExporter = true
                }
            #endif
        } label: {
            Image(systemName: "square.and.arrow.down")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .touchTarget() // 44pt touch floor on iPad, no-op on macOS (#597)
        .pointerHoverEffect() // pointer hover highlight on iPad (#586)
        .help(isMultiFile ? String(localized: "Download all files as a folder") : String(localized: "Download code"))
        .accessibilityLabel(isMultiFile
            ? String(localized: "Download all files as a folder")
            : String(localized: "Download code"))
    }

    /// A vertical list of the environment's files, pinned beside the code. It
    /// scrolls independently so even a project with many files stays browsable
    /// without the code pane having to grow.
    var fileSidebar: some View {
        ScrollView(.vertical, showsIndicators: false) {
            // Lazy so a project with many files only materializes the rows visible
            // at the top level (nested folders still build when expanded).
            LazyVStack(alignment: .leading, spacing: 2) {
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
        // A determinate height that matches the code viewport beside it. Without it
        // this vertical scroll is unbounded vertically *inside the detail pane's own
        // vertical scroll* — for a project with many files the sidebar drives the row
        // taller and the two vertical scrolls renegotiate combinatorially, the same
        // main-thread hang as the code view (#494). Pinning it keeps the file list
        // independently scrollable within a fixed row.
        .frame(width: CGFloat(sidebarWidth), height: 360)
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
                // Declarative cursor for a horizontal divider drag, replacing manual
                // NSCursor push/pop on hover (#287). macOS-only: iPadOS has no
                // equivalent pointer-shape API here.
                #if os(macOS)
                    .pointerStyle(.columnResize)
                #endif
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                // Measure each drag from the committed width and
                                // move only the lightweight preview indicator —
                                // the heavy panes stay put until release.
                                let next = sidebarWidth + Double(value.translation.width)
                                liveWidth = CodeSidebarWidth.clamped(next)
                            }
                            .onEnded { _ in
                                // Commit the previewed width (one relayout) and
                                // clear the preview.
                                if let liveWidth { storedWidth = liveWidth }
                                liveWidth = nil
                            }
                    )
                    // The divider is drag-only, so VoiceOver and keyboard users can't
                    // resize the file list. Expose it as one adjustable element whose
                    // increment/decrement nudges the width within the same 120–420
                    // bounds the drag clamps to (#351).
                    .accessibilityElement()
                    .accessibilityLabel("Code panel width")
                    .accessibilityValue(Text("\(Int(sidebarWidth))"))
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: storedWidth = CodeSidebarWidth.clamped(sidebarWidth + 20)
                        case .decrement: storedWidth = CodeSidebarWidth.clamped(sidebarWidth - 20)
                        @unknown default: break
                        }
                    }
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
        .touchTarget() // 44pt touch floor on iPad, no-op on macOS (#597)
        .pointerHoverEffect() // pointer hover highlight on iPad (#586)
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
                VStack(alignment: .leading, spacing: 12) {
                    if let explanation {
                        if explanation.sourceWasTruncated {
                            Label(
                                "This explanation covers only the beginning of the file.",
                                systemImage: "exclamationmark.triangle"
                            )
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        }
                        explanationSection(title: "What it does", text: explanation.summary)
                        explanationSection(title: "Quality & readability", text: explanation.readability)
                        explanationSection(title: "Time & space complexity", text: explanation.optimality)
                    } else if explanationFailed {
                        // A failed attempt says so and offers a retry, rather than the
                        // spinner just stopping as if the button did nothing (#790).
                        Text("The on-device model couldn't generate an explanation for this file.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button("Try Again") {
                            Task { await explainSelected() }
                        }
                        .disabled(isExplaining)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(width: 320, height: 300)
    }

    /// One titled paragraph of the explanation popover. Hidden when empty so a
    /// section the model left blank doesn't show a bare heading.
    @ViewBuilder
    private func explanationSection(title: LocalizedStringKey, text: String) -> some View {
        if !text.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                // The model returns Markdown (bold, inline code, lists), so render it
                // rather than showing the raw `**…**`/backtick markers as text (#342).
                MarkdownText(text)
                    .font(.callout)
                    .environment(\.isRasterizedForPrint, true)
            }
        }
    }

    /// Generates (or reuses) an on-device explanation of the visible file, then
    /// shows it in the popover. Reuses an explanation already generated for the
    /// same file revision (id, contents, and language, #789/#937) so reopening
    /// the popover is instant without re-running the model, but a refresh that
    /// rewrites the file at the same path regenerates.
    func explainSelected() async {
        // Snapshot the file the model actually sees: the sidebar stays enabled
        // while generating, so `selected` can move to another file mid-flight and
        // the result must stay tied to this one (#749).
        let file = selected
        let key = file.explanationKey
        if explanationKey == key, explanation != nil {
            showExplanation = true
            return
        }
        isExplaining = true
        explanationFailed = false
        defer { isExplaining = false }
        let result = await PadCodeExplainer.explain(file: file)
        // Only present/cache for the exact file revision still on screen. If the
        // user moved away, or a refresh changed the same path's contents/language,
        // the result belongs to stale input (#749, #937).
        guard selected.explanationKey == key else { return }

        if let result {
            explanation = result
            explanationKey = key
        }
        explanationFailed = result == nil
        showExplanation = true
    }

    var accessibilityLabel: String {
        // Name the environment by its language, the same identity shown visually.
        let environmentName = language.flatMap { $0.isEmpty ? nil : $0.coderPadLanguageDisplayName }
        if isMultiFile {
            if let environmentName {
                return String(localized: "Code preview of \(selected.name) in \(environmentName) in pad \(padID)")
            }
            return String(localized: "Code preview of \(selected.name) in pad \(padID)")
        }
        if let environmentName {
            return String(localized: "Code preview of \(environmentName) in pad \(padID)")
        }
        return String(localized: "Code preview of pad \(padID)")
    }
}
