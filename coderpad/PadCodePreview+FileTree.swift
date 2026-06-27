//
//  PadCodePreview+FileTree.swift
//  coderpad
//

import SwiftUI

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
        // on iPad (no-op on macOS, #597).
        .touchTarget()
        // VoiceOver otherwise reads only "‹name›, button" with no sense of whether
        // the folder is open. Speak the state as the element's value and describe
        // what activating it does (#351). macOS has no public `.isExpanded` trait.
        .accessibilityValue(collapsed ? "Collapsed" : "Expanded")
        .accessibilityHint(collapsed ? "Expands the folder" : "Collapses the folder")
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
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Match the folder row: raise the file row to the 44pt touch floor on iPad
        // (no-op on macOS, #597).
        .touchTarget()
        .help(file.path ?? file.name)
    }
}
