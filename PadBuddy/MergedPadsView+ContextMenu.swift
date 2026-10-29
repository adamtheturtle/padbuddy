//
//  MergedPadsView+ContextMenu.swift
//  coderpad
//
//  The per-row right-click menu and drag payload for the combined pads list's
//  `NSTableView`-backed `FastList`. Split out of MergedPadsView+List.swift to keep
//  that file under the line-length cap.
//

#if os(macOS)
    import AppKit
#endif
import FastList
import SwiftUI
import UniformTypeIdentifiers

extension MergedPadsView {
    /// The right-click menu for a combined-pads row, built as AppKit `MenuItem`s
    /// (the hosted content is hit-transparent, so a SwiftUI `.contextMenu` can't be
    /// used). A multi-row selection acts on the whole selection, Finder-style;
    /// otherwise it's the single-row menu. (Share is reachable from the detail pane.)
    func padTableMenuItems(_ row: AccountScoped<Account, Pad>) -> [MenuItem] {
        if selectedIDs.count > 1, selectedIDs.contains(row.id) {
            let rows = selectedRowsInOrder
            return [
                .button(title: String(localized: "Copy \(rows.count) Pad Links")) {
                    let links = padCopyURLs(rows)
                    guard !links.isEmpty else { return }

                    Clipboard.copy(links.joined(separator: "\n"))
                },
                .separator,
                .button(title: String(localized: "Delete \(rows.count) Pads…"),
                        isEnabled: !isReadOnly,
                        role: .destructive) {
                    padsPendingBulkDelete = rows
                }
            ]
        }
        let copyURL = row.item.webURL(fallbackBase: row.account.resolvedBaseURL)
        let starred = favoritePads.isFavorite(row.item.id, account: row.account.id)
        return [
            .button(title: String(localized: "Open Pad")) {
                selectedIDs = [row.id]
                openPad(row)
            },
            .button(title: starred ? String(localized: "Remove from Favorites")
                : String(localized: "Add to Favorites")) {
                    favoritePads.toggle(row.item.id, title: row.item.title, account: row.account.id,
                                        undoManager: undoManager)
                },
            .separator,
            .button(title: String(localized: "Copy Pad ID")) { Clipboard.copy(row.item.id) },
            .button(title: String(localized: "Copy Pad URL"), isEnabled: copyURL != nil) {
                guard let copyURL else { return }

                Clipboard.copy(copyURL.absoluteString)
            },
            .separator,
            .button(title: String(localized: "Show Only \(row.account.name)")) {
                accountFilter = row.account.id
            },
            .button(title: String(localized: "Show Pads from \(directory.display(row.item.ownerEmail))")) {
                ownerFilter = row.item.ownerEmail
            },
            .separator,
            .button(title: String(localized: "Delete…"), isEnabled: !isReadOnly, role: .destructive) {
                padPendingDelete = row
            }
        ]
    }

    func padCopyURLs(_ rows: [AccountScoped<Account, Pad>]) -> [String] {
        rows.compactMap { $0.item.webURL(fallbackBase: $0.account.resolvedBaseURL)?.absoluteString }
    }

    /// The iPad drag payload for a combined-pads row: the internal `FavoriteDrop` carrying
    /// the *originating* account (so it drops onto the sidebar Favorites and pins to the
    /// right account, #297) plus the web URL (so external drops still receive a link). `nil`
    /// — non-draggable — when the pad has no URL, mirroring `padPasteboardItem` on macOS.
    func padFavoritePayload(_ row: AccountScoped<Account, Pad>) -> FavoriteDragPayload? {
        guard let url = row.item.webURL(fallbackBase: row.account.resolvedBaseURL) else { return nil }

        return FavoriteDragPayload(
            drop: .pad(
                account: row.account.id,
                id: row.item.id,
                title: row.item.title.isEmpty ? row.item.id : row.item.title
            ),
            url: url
        )
    }

    // The drag payload for a combined-pads row: the pad's web URL (external link
    // drops) plus the internal `FavoriteDrop` JSON carrying the *originating* account
    // (so it drops onto the sidebar Favorites and pins to the right account, #297).
    #if os(macOS)
        func padPasteboardItem(_ row: AccountScoped<Account, Pad>) -> NSPasteboardItem? {
            if selectedIDs.count > 1, selectedIDs.contains(row.id) {
                return multiLinkPasteboardItem(padCopyURLs(selectedRowsInOrder))
            }

            guard let url = row.item.webURL(fallbackBase: row.account.resolvedBaseURL) else { return nil }

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
    #endif
}
