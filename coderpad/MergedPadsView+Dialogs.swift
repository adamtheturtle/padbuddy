//
//  MergedPadsView+Dialogs.swift
//  coderpad
//
//  The combined pads list's new-pad sheet, delete confirmations, and delete-error
//  alert, plus the open/delete row actions those confirmations trigger. Split out
//  of MergedPadsView+List.swift to keep each file within its length budget; it's
//  the last link in that file's `decorated` modifier chain (see the note there on
//  why the chain is split across `some View` steps).
//

import SwiftUI

extension MergedPadsView {
    // MARK: - Actions

    func openPad(_ pad: Pad) {
        guard let url = pad.webURL else { return }

        BrowserSettings.openExternally(url)
    }

    /// Delete a row's pad against its own account's client. The row carries its
    /// source account, so neither the route map (which collapses when two custom
    /// servers share a slug) nor a current-account fallback can send the delete to
    /// the wrong org (#758).
    func deletePad(_ row: AccountScoped<Account, Pad>) async {
        do {
            try await row.account.makeClient().deletePad(id: row.item.id)
            AppRouter.padDeleted(id: row.item.id)
        } catch {
            deleteError = error.localizedDescription
        }
    }

    // MARK: - Dialogs

    /// The new-pad sheet, delete confirmations, and delete-error alert.
    var decoratedDialogs: some View {
        decoratedStreams
            .sheet(item: $creatingForAccount) { account in
                NewPadSheet(
                    client: account.makeClient(),
                    targetAccountID: account.id,
                    keyOwnerEmail: account.userEmail,
                    initialQuestionID: creatingSeedQuestionID
                ) { created in
                    insert(created, into: account)
                    selectedIDs = [Self.rowID(account: account.id, pad: created.id)]
                    creatingForAccount = nil
                    creatingSeedQuestionID = nil
                } onCancel: {
                    creatingForAccount = nil
                    creatingSeedQuestionID = nil
                }
            }
            .alert(
                "Delete this pad?",
                isPresented: .init(get: { padPendingDelete != nil },
                                   set: { if !$0 { padPendingDelete = nil } }),
                presenting: padPendingDelete
            ) { row in
                Button("Cancel", role: .cancel) {}
                Button("Delete Pad", role: .destructive) { Task { await deletePad(row) } }
            } message: { row in
                Text("“\(row.item.title)” will be permanently deleted. This can't be undone.")
            }
            .alert(
                "Delete \(padsPendingBulkDelete?.count ?? 0) pads?",
                isPresented: .init(get: { padsPendingBulkDelete != nil },
                                   set: { if !$0 { padsPendingBulkDelete = nil } }),
                presenting: padsPendingBulkDelete
            ) { rows in
                Button("Cancel", role: .cancel) {}
                Button("Delete \(rows.count) Pads", role: .destructive) {
                    scheduleBulkDelete(rows)
                }
            }
            .alert("Couldn't delete pad",
                   isPresented: .init(get: { deleteError != nil },
                                      set: { if !$0 { deleteError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteError ?? "")
            }
            .overlay(alignment: .bottom) { bulkDeleteUndoBanner }
    }
}
