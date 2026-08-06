//
//  PadHistoryPlayback+Context.swift
//  coderpad
//
//  File selection for playback tracks.
//

import SwiftUI

extension HistoryPlaybackView {
    /// A vertical file browser matching the code card's project file list, so
    /// session playback uses the same file navigation pattern as the current code view.
    func historyFileBrowser(width: Double) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 2) {
                FileTreeRows(
                    nodes: historyFileTree,
                    depth: 0,
                    selectedID: displayedFile?.id ?? histories.first?.id ?? "",
                    collapsedFolders: $collapsedHistoryFolders,
                    onSelect: { manualFileID = $0 }
                )
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: CGFloat(width), height: 560, alignment: .leading)
        .accessibilityLabel("History files")
    }

    private var historyFileTree: [FileTreeNode] {
        let entries: [(segments: [String], file: FileTreeLeaf)] = histories.map { history in
            var segments: [String] = history.title.split(separator: "/")
                .map(String.init)
                .filter { $0 != "." && $0 != ".." }
            if segments.count > EnvironmentCodeCard.maxTreeDepth {
                segments = Array(segments.prefix(EnvironmentCodeCard.maxTreeDepth - 1))
                    + [segments.suffix(from: EnvironmentCodeCard.maxTreeDepth - 1).joined(separator: "/")]
            }
            let title = history.title.isEmpty ? "untitled" : history.title
            let leafName = segments.last ?? title
            let leaf = FileTreeLeaf(id: history.id, name: leafName, path: history.title)
            return (segments.isEmpty ? [title] : segments, leaf)
        }
        return EnvironmentCodeCard.makeNodes(entries: entries, prefix: "")
    }
}
