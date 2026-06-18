//
//  MergedQuestionsView+ContextMenu.swift
//  coderpad
//
//  The per-row and multi-row right-click context menus for the combined questions
//  list. Split out of MergedQuestionsView+List.swift to keep it under the line cap.
//

import SwiftUI

extension MergedQuestionsView {
    @ViewBuilder
    func questionContextMenu(_ row: AccountScoped<Question>) -> some View {
        // Right-clicking a row that's part of a multi-row selection copies every
        // selected link at once, Finder-style; a single row keeps its full menu.
        if selectedRowIDs.count > 1, selectedRowIDs.contains(row.id) {
            bulkSelectionContextMenu()
        } else {
            Button {
                select(row)
                nav.createPadForQuestionID = row.item.id
            } label: {
                Label("New Pad from Question", systemImage: "plus.rectangle.on.rectangle")
            }
            .disabled(isReadOnly)
            Button {
                toggleFavorite(row)
            } label: {
                Label(isFavorite(row) ? "Remove from Favorites" : "Add to Favorites",
                      systemImage: isFavorite(row) ? "star.slash" : "star")
            }
            ShareLink(item: row.item.webURL(baseURL: row.account.resolvedBaseURL)) {
                Label("Share…", systemImage: "square.and.arrow.up")
            }
            Divider()
            Button { Clipboard.copy(row.item.displayTitle) } label: {
                Label("Copy Title", systemImage: "doc.on.doc")
            }
            Button { Clipboard.copy(row.item.webURL(baseURL: row.account.resolvedBaseURL).absoluteString) } label: {
                Label("Copy Question URL", systemImage: "link")
            }
            Button { accountFilter = row.account.id } label: {
                Label("Show Only \(row.account.name)", systemImage: "person.crop.circle")
            }
            Divider()
            Button(role: .destructive) {
                select(row)
                nav.deleteQuestionID = row.item.id
            } label: {
                Label("Delete Question…", systemImage: "trash")
            }
            .disabled(isReadOnly)
        }
    }

    @ViewBuilder
    private func bulkSelectionContextMenu() -> some View {
        let rows = selectedRowsInOrder
        Button {
            Clipboard.copy(rows
                .map { $0.item.webURL(baseURL: $0.account.resolvedBaseURL).absoluteString }
                .joined(separator: "\n"))
        } label: {
            Label("Copy \(rows.count) Question Links", systemImage: "link")
        }
        Divider()
        Button(role: .destructive) {
            rowsPendingBulkDelete = rows
        } label: {
            Label("Delete \(rows.count) Questions…", systemImage: "trash")
        }
        .disabled(isReadOnly)
    }
}
