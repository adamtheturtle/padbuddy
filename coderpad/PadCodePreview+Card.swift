//
//  PadCodePreview+Card.swift
//  coderpad
//

// swiftlint:disable file_length

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
            if isMultiFile {
                fileSidebarButton
            }
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

    private var fileSidebarButton: some View {
        Button {
            isFileSidebarVisible.toggle()
            liveWidth = nil
        } label: {
            Image(systemName: isFileSidebarVisible ? "sidebar.left" : "sidebar.left")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .touchTarget()
        .pointerHoverEffect()
        .help(isFileSidebarVisible ? "Hide file sidebar" : "Show file sidebar")
        .accessibilityLabel(isFileSidebarVisible ? "Hide file sidebar" : "Show file sidebar")
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
                        exportError = String(localized: "Could not prepare the code archive to save.")
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
    func fileSidebar(width: Double) -> some View {
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
        .frame(width: CGFloat(width), height: 360)
    }

    /// The draggable divider between the file list and the code. It draws the
    /// same hairline as a plain `Divider` but carries a wider, invisible hit
    /// target so the resize is easy to grab, and shows the left/right resize
    /// cursor on hover. Dragging only moves a preview line (`liveWidth`); the new
    /// width is committed to `storedWidth` on release so the panes relayout once,
    /// not on every frame.
    func resizeHandle(sidebarWidth: Double, availableWidth: Double) -> some View {
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
                                liveWidth = CodeSidebarWidth.effective(
                                    next, availableWidth: availableWidth
                                )
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
                        case .increment:
                            storedWidth = CodeSidebarWidth.effective(
                                sidebarWidth + 20, availableWidth: availableWidth
                            )

                        case .decrement:
                            storedWidth = CodeSidebarWidth.effective(
                                sidebarWidth - 20, availableWidth: availableWidth
                            )

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
        Group {
            if selected.isBinary {
                ContentUnavailableView("Binary file", systemImage: "doc.badge.ellipsis",
                                       description: Text("A text preview is unavailable."))
            } else {
                HighlightedCode(
                    contents: selected.contents,
                    language: selected.language,
                    dark: dark,
                    fontScale: codeFontScale
                )
                .equatable()
            }
        }
    }

    /// Explains the selected file on device in an anchored popover. Nothing runs
    /// until the user taps, and the button is disabled during generation.
    private var explainButton: some View {
        Button {
            startExplanation()
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
        .popover(isPresented: explanationPresentation, arrowEdge: .bottom) {
            explanationPopover
        }
    }

    private var explanationPresentation: Binding<Bool> {
        Binding(get: { showExplanation }, set: { presented in
            showExplanation = presented
            if !presented, isExplaining { cancelExplanation() }
        })
    }

    private var explanationPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Explanation", systemImage: "sparkles")
                .font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    let explanation = explanations[selected.explanationKey]
                    switch CodeExplanationPresentationState.resolve(
                        hasResult: explanation != nil,
                        isExplaining: isExplaining,
                        failed: explanationFailed
                    ) {
                    case .loading:
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Generating an on-device explanation…")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Button("Cancel", role: .cancel) {
                                cancelExplanation()
                                showExplanation = false
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 180)

                    case .result:
                        if let explanation {
                            Text("Code revision: \(selected.revisionIdentifier)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Code revision \(selected.revisionIdentifier)")
                            Button {
                                Clipboard.copy(explanation.plainText(
                                    revisionIdentifier: selected.revisionIdentifier
                                ))
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                            explanationContent(explanation)
                        }

                    case .failed:
                        Text("The on-device model could not generate an explanation for this file.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        if explanationUsesReducedContext {
                            Button("Try Again") { startExplanation(reducedContext: true) }
                        } else {
                            Button("Retry with Shorter Excerpt") { startExplanation(reducedContext: true) }
                            Text("Uses less source code to fit the model context.").font(.caption)
                        }

                    case .empty:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(width: 320, height: 300)
    }

    @ViewBuilder
    private func explanationContent(_ explanation: CodeExplanation) -> some View {
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
