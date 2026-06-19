//
//  MergedPadsView+ContextMenu.swift
//  coderpad
//
//  The per-row right-click menu and drag payload for the combined pads list's
//  `NSTableView`-backed `ListTable`. Split out of MergedPadsView+List.swift to keep
//  that file under the line-length cap.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension MergedPadsView {
    /// The right-click menu for a combined-pads row, built as AppKit `RowMenuItem`s
    /// (the hosted content is hit-transparent, so a SwiftUI `.contextMenu` can't be
    /// used). A multi-row selection acts on the whole selection, Finder-style;
    /// otherwise it's the single-row menu. (Share is reachable from the detail pane.)
    func padTableMenuItems(_ row: AccountScoped<Pad>) -> [RowMenuItem] {
        if selectedIDs.count > 1, selectedIDs.contains(row.item.id) {
            let pads = selectedPadsInOrder
            return [
                .button(title: String(localized: "Copy \(pads.count) Pad Links")) {
                    Clipboard.copy(pads.map(\.url).joined(separator: "\n"))
                },
                .separator,
                .button(title: String(localized: "Delete \(pads.count) Pads…"),
                        isDestructive: true, isEnabled: !isReadOnly) {
                    padsPendingBulkDelete = pads
                }
            ]
        }
        let starred = favoritePads.isFavorite(row.item.id, account: row.account.id)
        return [
            .button(title: String(localized: "Open Pad")) {
                selectedIDs = [row.item.id]
                openPad(row.item)
            },
            .button(title: starred ? String(localized: "Remove from Favorites")
                : String(localized: "Add to Favorites")) {
                    favoritePads.toggle(row.item.id, account: row.account.id)
                },
            .separator,
            .button(title: String(localized: "Copy Pad ID")) { Clipboard.copy(row.item.id) },
            .button(title: String(localized: "Copy Pad URL")) { Clipboard.copy(row.item.url) },
            .separator,
            .button(title: String(localized: "Show Only \(row.account.name)")) {
                accountFilter = row.account.id
            },
            .button(title: String(localized: "Show Pads from \(directory.display(row.item.ownerEmail))")) {
                ownerFilter = row.item.ownerEmail
            },
            .separator,
            .button(title: String(localized: "Delete…"), isDestructive: true, isEnabled: !isReadOnly) {
                padPendingDelete = row.item
            }
        ]
    }

    /// The drag payload for a combined-pads row: the pad's web URL (external link
    /// drops) plus the internal `FavoriteDrop` JSON carrying the *originating* account
    /// (so it drops onto the sidebar Favorites and pins to the right account, #297).
    func padPasteboardItem(_ row: AccountScoped<Pad>) -> NSPasteboardItem? {
        guard let url = row.item.webURL else { return nil }

        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .URL)
        item.setString(url.absoluteString, forType: .string)
        if let data = try? JSONEncoder().encode(FavoriteDrop.pad(
            account: row.account.id,
            id: row.item.id,
            title: row.item.title.isEmpty ? row.item.id : row.item.title
        )) {
            item.setData(data, forType: NSPasteboard.PasteboardType(UTType.coderpadFavorite.identifier))
        }
        return item
    }
}
