//
//  PadCodePreview+FileTree.swift
//  coderpad
//

import SwiftUI

/// A displayable file row in a file tree.
struct FileTreeLeaf: Identifiable {
    let id: String
    let name: String
    let path: String?
}

/// A node in the file tree built from file paths. A leaf carries a
/// `file`; a folder carries `children` and a nil `file`.
struct FileTreeNode: Identifiable {
    let id: String
    let name: String
    let file: FileTreeLeaf?
    let children: [Self]

    var isFolder: Bool {
        file == nil
    }
}

/// A small memo for built file trees, keyed by the file set's identity, so a
/// parent body pass that re-inits the card (which happens per render) reuses
/// the previous recursive grouping + deterministic sort instead of re-running it
/// for every card instance on the main actor (#1179).
@MainActor
enum FileTreeMemo {
    private static var trees: [Int: [FileTreeNode]] = [:]
    private static var order: [Int] = []

    static func tree(for files: [CodeFile]) -> [FileTreeNode] {
        var hasher = Hasher()
        for file in files {
            hasher.combine(file.id)
            hasher.combine(file.path)
        }
        let key = hasher.finalize()
        if let cached = trees[key] { return cached }

        let built = EnvironmentCodeCard.makeFileTree(from: files)
        trees[key] = built
        order.append(key)
        // A pad shows a handful of environments at once; keep the memo small.
        while order.count > 8 {
            trees[order.removeFirst()] = nil
        }
        return built
    }
}

extension EnvironmentCodeCard {
    /// Deepest folder nesting the tree renders: a server-provided path with
    /// thousands of segments would otherwise recurse once per segment while
    /// building the tree and could stall the main actor or overflow the stack;
    /// deeper tails collapse into the leaf's displayed name (#1178).
    static let maxTreeDepth = 32

    /// Builds the folder tree from a flat file list. Pure and static so it can run
    /// once per distinct file set (see `FileTreeMemo`).
    static func makeFileTree(from files: [CodeFile]) -> [FileTreeNode] {
        // Explicitly-typed intermediates keep the tuple-returning map cheap to
        // type-check; the inferred chain otherwise blows the 250ms budget on CI's
        // slower toolchain (#427).
        let entries: [(segments: [String], file: FileTreeLeaf)] = files.map { file in
            let path = file.path ?? file.name
            var segments: [String] = path.split(separator: "/")
                .map(String.init)
                .filter { $0 != "." && $0 != ".." }
            if segments.count > Self.maxTreeDepth {
                segments = Array(segments.prefix(Self.maxTreeDepth - 1))
                    + [segments.suffix(from: Self.maxTreeDepth - 1).joined(separator: "/")]
            }
            let leaf = FileTreeLeaf(id: file.id, name: file.name, path: file.path)
            return (segments.isEmpty ? [file.name] : segments, leaf)
        }
        return makeNodes(entries: entries, prefix: "")
    }

    static func makeNodes(
        entries: [(segments: [String], file: FileTreeLeaf)],
        prefix: String
    ) -> [FileTreeNode] {
        var folderOrder: [String] = []
        var groups: [String: [(segments: [String], file: FileTreeLeaf)]] = [:]
        var leaves: [(name: String, file: FileTreeLeaf)] = []

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
        // Paths are machine identifiers, not prose. Swift's locale-independent
        // lexical order keeps the same source tree stable on every machine (#1911).
        for folder in folderOrder.sorted() {
            let childPrefix = prefix.isEmpty ? folder : prefix + "/" + folder
            let children = makeNodes(entries: groups[folder] ?? [], prefix: childPrefix)
            nodes.append(FileTreeNode(id: "folder:" + childPrefix, name: folder, file: nil, children: children))
        }
        for leaf in leaves.sorted(by: { $0.name < $1.name }) {
            nodes.append(FileTreeNode(id: "file:\(leaf.file.id)", name: leaf.name, file: leaf.file, children: []))
        }
        return nodes
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
    /// The folder disclosure chevron's point size, scaled with the user's preferred
    /// text size (tracking Caption 2, matching the adjacent caption-sized labels).
    @ScaledMetric(relativeTo: .caption2) private var disclosureChevronSize: CGFloat = 9

    var body: some View {
        ForEach(nodes) { node in
            if node.isFolder {
                folderRow(node)
                if !collapsedFolders.contains(node.id) {
                    Self(
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
                    .font(.system(size: disclosureChevronSize, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 10)
                    .accessibilityHidden(true)
                Image(systemName: "folder")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
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
        // ~26pt tall (caption + 5pt v-padding); raise the row to the 44pt touch floor
        // on iPad (no-op on macOS, #597), and highlight it under the iPad pointer (#586).
        .touchTarget()
        .pointerHoverEffect()
        // VoiceOver otherwise reads only "‹name›, button" with no sense of whether
        // the folder is open. Speak the state as the element's value and describe
        // what activating it does (#351). macOS has no public `.isExpanded` trait.
        .accessibilityValue(collapsed ? "Collapsed" : "Expanded")
        .accessibilityHint(collapsed ? "Expands the folder" : "Collapses the folder")
    }

    private func fileRow(_: FileTreeNode, file: FileTreeLeaf) -> some View {
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
                    .accessibilityHidden(true)
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
                in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
            )
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Match the folder row: raise the file row to the 44pt touch floor on iPad
        // (no-op on macOS, #597), and highlight it under the iPad pointer (#586).
        .touchTarget()
        .pointerHoverEffect()
        .help(file.path ?? file.name)
    }
}
