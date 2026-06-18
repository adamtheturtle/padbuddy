//
//  MergedPadsView+ContextMenu.swift
//  coderpad
//
//  The per-row and multi-row right-click context menus for the combined pads list.
//  Split out of MergedPadsView+List.swift to keep that file under the line-length cap.
//

import SwiftUI

extension MergedPadsView {
    @ViewBuilder
    func padContextMenu(_ row: AccountScoped<Pad>) -> some View {
        // Right-clicking a row that's part of a multi-row selection acts on the whole
        // selection, the way Finder does; otherwise it's the usual single-row menu.
        if selectedIDs.count > 1, selectedIDs.contains(row.item.id) {
            bulkContextMenu
        } else {
            Button {
                selectedIDs = [row.item.id]
                openPad(row.item)
            } label: {
                Label("Open Pad", systemImage: "doc.text.image")
            }
            if let url = row.item.webURL {
                ShareLink(item: url) { Label("Share…", systemImage: "square.and.arrow.up") }
            }
            Divider()
            Button { Clipboard.copy(row.item.id) } label: {
                Label("Copy Pad ID", systemImage: "number")
            }
            Button { Clipboard.copy(row.item.url) } label: {
                Label("Copy Pad URL", systemImage: "link")
            }
            Divider()
            Button { accountFilter = row.account.id } label: {
                Label("Show Only \(row.account.name)", systemImage: "person.crop.circle")
            }
            Button { ownerFilter = row.item.ownerEmail } label: {
                Label("Show Pads from \(directory.display(row.item.ownerEmail))", systemImage: "person")
            }
            Divider()
            Button(role: .destructive) {
                padPendingDelete = row.item
            } label: {
                Label("Delete…", systemImage: "trash")
            }
            .disabled(isReadOnly)
        }
    }

    /// The actions offered when right-clicking inside a multi-row selection: copy
    /// every selected pad's link at once, or delete them all (behind a confirmation).
    @ViewBuilder
    private var bulkContextMenu: some View {
        let pads = selectedPadsInOrder
        Button {
            Clipboard.copy(pads.map(\.url).joined(separator: "\n"))
        } label: {
            Label("Copy \(pads.count) Pad Links", systemImage: "link")
        }
        Divider()
        Button(role: .destructive) {
            padsPendingBulkDelete = pads
        } label: {
            Label("Delete \(pads.count) Pads…", systemImage: "trash")
        }
        .disabled(isReadOnly)
    }
}
