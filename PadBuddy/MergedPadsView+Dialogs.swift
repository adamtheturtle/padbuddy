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

    /// Open a pad in the user's configured browser. Resolved via the owning
    /// account's base URL when the pad's own `url` field is absent or malformed,
    /// so pads from self-hosted/regional servers still open (#1010). The selected
    /// row's published account is preferred over the collision-prone route map,
    /// then the current account, mirroring the detail pane's routing (#758).
    func openPad(_ pad: Pad) {
        let routed = selection?.id == pad.id
            ? router.selectedPadAccountID.flatMap { id in accounts.accounts.first { $0.id == id } }
            : nil
        let account = routed ?? router.account(forPadID: pad.id) ?? accounts.currentAccount
        openPad(pad, account: account)
    }

    /// Open using the row's owning account directly so a colliding slug cannot
    /// route to another server before selection routing publishes (#4674).
    func openPad(_ row: AccountScoped<Account, Pad>) {
        openPad(row.item, account: row.account)
    }

    private func openPad(_ pad: Pad, account: Account?) {
        let base = account?.resolvedBaseURL ?? CoderPadClient.defaultBaseURL
        guard let url = pad.webURL(fallbackBase: base) else { return }

        if let accountID = account?.id {
            PadOpenedStore.shared.record(pad.id, account: accountID)
        }
        BrowserSettings.openExternally(url)
    }

    /// Delete a row's pad against its live account client. Re-resolve the account
    /// against the current store so a remove/re-key while the confirm alert is
    /// open cannot fire DELETE with revoked credentials (#4673).
    func deletePad(_ row: AccountScoped<Account, Pad>) async {
        guard let current = accounts.accounts.first(where: { $0.id == row.account.id }),
              !current.pointsAtDifferentBackend(than: row.account) else {
            deleteError = BulkDeleteUndo.CredentialsChangedError.accountRemovedOrRekeyed
                .localizedDescription
            return
        }

        do {
            let client = current.makeClient()
            try await client.deletePad(id: row.item.id)
            AppRouter.padDeleted(id: row.item.id, account: row.account.id, via: client)
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
                    initialQuestionID: creatingSeedQuestionID,
                    initialError: creatingFallbackError
                ) { created in
                    insert(created, into: account)
                    selectedIDs = [Self.rowID(account: account.id, pad: created.id)]
                    creatingForAccount = nil
                    creatingSeedQuestionID = nil
                    creatingFallbackError = nil
                } onCancel: {
                    creatingForAccount = nil
                    creatingSeedQuestionID = nil
                    creatingFallbackError = nil
                }
            }
            .alert(
                "Delete this pad?",
                isPresented: .init(get: { padPendingDelete != nil },
                                   set: {
                                       if !$0 {
                                           padPendingDelete = nil
                                       }
                                   }),
                presenting: padPendingDelete
            ) { row in
                Button("Cancel", role: .cancel) {}
                Button("Delete Pad", role: .destructive) { Task { await deletePad(row) } }
            } message: { row in
                Text("“\(row.item.title)” will be permanently deleted. This cannot be undone.")
            }
            .alert(
                "Delete \(padsPendingBulkDelete?.count ?? 0) pads?",
                isPresented: .init(get: { padsPendingBulkDelete != nil },
                                   set: {
                                       if !$0 {
                                           padsPendingBulkDelete = nil
                                       }
                                   }),
                presenting: padsPendingBulkDelete
            ) { rows in
                Button("Cancel", role: .cancel) {}
                Button("Delete \(rows.count) Pads", role: .destructive) {
                    scheduleBulkDelete(rows)
                }
            }
            .alert("Could not delete pad",
                   isPresented: .init(get: { deleteError != nil },
                                      set: {
                                          if !$0 {
                                              deleteError = nil
                                          }
                                      })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteError ?? "")
            }
            .alert("Pad unavailable",
                   isPresented: .init(get: { unavailablePadID != nil },
                                      set: {
                                          if !$0 {
                                              unavailablePadID = nil
                                          }
                                      })) {
                if !isReadOnly {
                    Button("Create New Pad") { creatingForAccount = newPadDefaultAccount }
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text("Pad \(unavailablePadID ?? "") is no longer available. The Pads list is open instead.")
            }
            .overlay(alignment: .bottom) { bulkDeleteUndoBanner }
            // A pending bulk delete must die with the list: once the view (and its
            // Undo banner) is gone, letting the grace-period task fire would delete
            // with no remaining way to undo (#1018, mirroring #870).
            .onDisappear { cancelBulkDelete() }
    }
}
