//
//  PadCodePreview+FullView.swift
//  coderpad
//

import SwiftUI

extension EnvironmentCodeCard {
    /// A large, full-screen reader for the environment's code. The inline card pins
    /// its code to a 360-tall viewport (the fix for the nested-scroll hang, #494);
    /// presented in a sheet this fills the available space instead, so a long file
    /// can be read without that clamp. Here the code scroll *is* the outer scroll,
    /// so `fillsHeight` is safe — there's no enclosing vertical scroll to renegotiate.
    @ViewBuilder
    var fullCodeViewer: some View {
        VStack(spacing: 0) {
            fullCodeBar
            Divider()
            if isMultiFile {
                HStack(alignment: .top, spacing: 0) {
                    fullFileSidebar
                    Divider()
                    fullCodeScroll
                }
            } else {
                fullCodeScroll
            }
        }
        #if os(macOS)
        // Give the sheet a generously large default size on the Mac, where a sheet
        // otherwise shrinks to fit its content.
        .frame(minWidth: 720, idealWidth: 900, minHeight: 560, idealHeight: 720)
        #endif
    }

    /// The title bar of the full-screen viewer: the file being shown, its language,
    /// and a Done button to dismiss. A plain bar rather than a navigation title so it
    /// reads the same on macOS and iPad.
    private var fullCodeBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.left.slash.chevron.right")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(isMultiFile ? selected.name : (language?.coderPadLanguageDisplayName ?? String(localized: "Code")))
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            if let language, !language.isEmpty, isMultiFile {
                MetaLabel(text: language.coderPadLanguageDisplayName)
            }
            Spacer(minLength: 12)
            Button(String(localized: "Done")) {
                showFullCode = false
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// The code pane, filling the viewer's height so the whole file is readable.
    private var fullCodeScroll: some View {
        HighlightedCode(contents: selected.contents, language: selected.language, dark: dark, fillsHeight: true)
            .equatable()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The file list for multi-file projects, mirroring the card's sidebar but
    /// filling the viewer's height instead of the fixed 360.
    private var fullFileSidebar: some View {
        ScrollView(.vertical, showsIndicators: false) {
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
        .frame(width: CGFloat(sidebarWidth), alignment: .leading)
        .frame(maxHeight: .infinity)
    }
}
