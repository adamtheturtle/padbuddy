//
//  MergedPadsView+Dialogs.swift
//  coderpad
//
//  The combined pads list's new-pad sheet, smart-filter sheet, delete confirmations,
//  and delete-error alert. Split out of MergedPadsView+List.swift to keep each file
//  within its length budget; it's the last link in that file's `decorated` modifier
//  chain (see the note there on why the chain is split across `some View` steps).
//

import SwiftUI

extension MergedPadsView {
    /// The new-pad sheet, delete confirmations, and delete-error alert.
    var decoratedDialogs: some View {
        decoratedStreams
            .sheet(item: $creatingForAccount) { account in
                NewPadSheet(client: account.makeClient(), initialQuestionID: creatingSeedQuestionID) { created in
                    insert(created, into: account)
                    selectedIDs = [created.id]
                    creatingForAccount = nil
                    creatingSeedQuestionID = nil
                } onCancel: {
                    creatingForAccount = nil
                    creatingSeedQuestionID = nil
                }
            }
            .sheet(isPresented: $showSmartFilter) {
                SmartFilterSheet(
                    text: $smartFilterText,
                    isInterpreting: isInterpreting,
                    failed: smartFilterFailed,
                    placeholder: "e.g. active Python pads",
                    failedMessage: "Couldn't turn that into filters. Try naming a language, owner, state, or date.",
                    hintMessage: "Mention a language, owner, state, or date.",
                    onSubmit: { Task { await applySmartFilter() } },
                    onCancel: { showSmartFilter = false }
                )
            }
            .confirmationDialog(
                "Delete this pad?",
                isPresented: .init(get: { padPendingDelete != nil },
                                   set: { if !$0 { padPendingDelete = nil } }),
                titleVisibility: .visible,
                presenting: padPendingDelete
            ) { pad in
                Button("Delete Pad", role: .destructive) { Task { await deletePad(pad) } }
                Button("Cancel", role: .cancel) {}
            } message: { pad in
                Text("“\(pad.title)” will be permanently deleted. This can't be undone.")
            }
            .confirmationDialog(
                "Delete \(padsPendingBulkDelete?.count ?? 0) pads?",
                isPresented: .init(get: { padsPendingBulkDelete != nil },
                                   set: { if !$0 { padsPendingBulkDelete = nil } }),
                titleVisibility: .visible,
                presenting: padsPendingBulkDelete
            ) { pads in
                Button("Delete \(pads.count) Pads", role: .destructive) {
                    scheduleBulkDelete(pads)
                }
                Button("Cancel", role: .cancel) {}
            } message: { pads in
                Text("You'll have a few seconds to undo before these \(pads.count) pads are permanently deleted.")
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
