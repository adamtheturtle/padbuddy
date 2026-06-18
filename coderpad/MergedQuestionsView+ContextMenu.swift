//
//  MergedQuestionsView+ContextMenu.swift
//  coderpad
//
//  The per-row right-click menu and drag payload for the combined questions list's
//  `NSTableView`-backed `ListTable`. Split out of MergedQuestionsView+List.swift to
//  keep it under the line cap.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension MergedQuestionsView {
    /// The right-click menu for a combined-questions row, built as AppKit
    /// `RowMenuItem`s (the hosted content is hit-transparent, so a SwiftUI
    /// `.contextMenu` can't be used). A multi-row selection acts on the whole
    /// selection, Finder-style; otherwise it's the single-row menu. Actions needing the
    /// detail pane select the row first, then route through `AppNavigation`. (Share is
    /// reachable from the detail pane.)
    func questionTableMenuItems(_ row: AccountScoped<Question>) -> [RowMenuItem] {
        if selectedRowIDs.count > 1, selectedRowIDs.contains(row.id) {
            let rows = selectedRowsInOrder
            return [
                .button(title: String(localized: "Copy \(rows.count) Question Links")) {
                    Clipboard.copy(rows
                        .map { $0.item.webURL(baseURL: $0.account.resolvedBaseURL).absoluteString }
                        .joined(separator: "\n"))
                },
                .separator,
                .button(title: String(localized: "Delete \(rows.count) Questions…"),
                        isDestructive: true, isEnabled: !isReadOnly) {
                    rowsPendingBulkDelete = rows
                },
            ]
        }
        let starred = isFavorite(row)
        return [
            .button(title: String(localized: "New Pad from Question"), isEnabled: !isReadOnly) {
                select(row)
                nav.createPadForQuestionID = row.item.id
            },
            .button(title: starred ? String(localized: "Remove from Favorites")
                : String(localized: "Add to Favorites")) {
                toggleFavorite(row)
            },
            .separator,
            .button(title: String(localized: "Copy Title")) { Clipboard.copy(row.item.displayTitle) },
            .button(title: String(localized: "Copy Question URL")) {
                Clipboard.copy(row.item.webURL(baseURL: row.account.resolvedBaseURL).absoluteString)
            },
            .button(title: String(localized: "Show Only \(row.account.name)")) {
                accountFilter = row.account.id
            },
            .separator,
            .button(title: String(localized: "Delete Question…"), isDestructive: true, isEnabled: !isReadOnly) {
                select(row)
                nav.deleteQuestionID = row.item.id
            },
        ]
    }

    /// The drag payload for a combined-questions row: its web URL (resolved against the
    /// originating account's server, external link drops) plus the internal
    /// `FavoriteDrop` JSON carrying that account (so it drops onto the sidebar
    /// Favorites and pins to the right account, #297).
    func questionPasteboardItem(_ row: AccountScoped<Question>) -> NSPasteboardItem? {
        let url = row.item.webURL(baseURL: row.account.resolvedBaseURL)
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .URL)
        item.setString(url.absoluteString, forType: .string)
        if let data = try? JSONEncoder().encode(FavoriteDrop.question(
            account: row.account.id,
            id: row.item.id,
            title: row.item.displayTitle
        )) {
            item.setData(data, forType: NSPasteboard.PasteboardType(UTType.coderpadFavorite.identifier))
        }
        return item
    }
}
