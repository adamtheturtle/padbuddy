//
//  MergedPadsView+Dialogs.swift
//  coderpad
//
//  The combined pads list's new-pad sheet, delete confirmations, and delete-error
//  alert. Split out of MergedPadsView+List.swift to keep each file
//  within its length budget; it's the last link in that file's `decorated` modifier
//  chain (see the note there on why the chain is split across `some View` steps).
//

import SwiftUI

extension MergedPadsView {
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
                    selectedIDs = [created.id]
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
            ) { pad in
                Button("Cancel", role: .cancel) {}
                Button("Delete Pad", role: .destructive) { Task { await deletePad(pad) } }
            } message: { pad in
                Text("“\(pad.title)” will be permanently deleted. This can't be undone.")
            }
            .alert(
                "Delete \(padsPendingBulkDelete?.count ?? 0) pads?",
                isPresented: .init(get: { padsPendingBulkDelete != nil },
                                   set: { if !$0 { padsPendingBulkDelete = nil } }),
                presenting: padsPendingBulkDelete
            ) { pads in
                Button("Cancel", role: .cancel) {}
                Button("Delete \(pads.count) Pads", role: .destructive) {
                    scheduleBulkDelete(pads)
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
