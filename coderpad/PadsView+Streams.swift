//
//  PadsView+Streams.swift
//  coderpad
//
//  The single-account pads list's AppRouter stream consumers (reload requests and
//  pad create/update/delete broadcasts), split from PadsView.swift to keep that
//  file within the lint length limit.
//

import SwiftUI

extension PadsView {
    /// The reload / pad-update / pad-creation / pad-deletion router streams.
    var decoratedStreams: some View {
        decoratedObservers
            .onReloadRequest { await reload() }
            .task {
                for await mutation in AppRouter.padUpdates {
                    // Scope to this list's account when the broadcast carries one:
                    // custom servers can issue colliding slugs, and an id-only match
                    // let account A's edit overwrite account B's same-slug row (#761).
                    guard mutation.account == nil || mutation.account == owningAccountID else { continue }

                    let updated = mutation.pad
                    if let index = pads.firstIndex(where: { $0.id == updated.id }) {
                        pads[index] = updated
                        padsRevision += 1
                        if selection?.id == updated.id { selection = updated }
                    }
                }
            }
            .task {
                for await creation in AppRouter.padCreations {
                    // A pad created outside the lists (widget, menu-bar extra, New Pad
                    // from Question) appears immediately rather than waiting for the
                    // next reload (#1251). Scoped to this list's account; the shared
                    // cache is updated by the creator, so only the rows update here.
                    guard creation.account == nil || creation.account == owningAccountID,
                          !pads.contains(where: { $0.id == creation.pad.id }) else { continue }

                    pads.insert(creation.pad, at: 0)
                    padsRevision += 1
                }
            }
            .task {
                for await deletion in AppRouter.padDeletions {
                    // Same account scoping as the update stream (#761).
                    guard deletion.account == nil || deletion.account == owningAccountID else { continue }

                    let id = deletion.id
                    // Drop the deleted id from the selection. If it was the primary,
                    // move to a neighbor (computed while `pads` still holds the row)
                    // only when no other rows stay selected; otherwise the primary
                    // falls to a still-selected row via the `selectedIDs` observer.
                    let wasPrimary = selection?.id == id
                    let neighbor = wasPrimary ? neighborSelection(forDeleted: id) : nil
                    selectedIDs.remove(id)
                    pads.removeAll { $0.id == id }
                    padsRevision += 1
                    // Keep the disk cache, Spotlight index, and widget in step;
                    // otherwise the deleted pad lingers there until a full reload.
                    cache.removePad(id: id, account: deletion.account)
                    if wasPrimary, selectedIDs.isEmpty {
                        selectedIDs = neighbor.map { [$0.id] } ?? []
                    }
                }
            }
    }

    /// The account this list belongs to, resolved from its own client so pad
    /// mutation broadcasts can be matched against the right account: custom
    /// servers can issue colliding slugs across accounts (#761). Falls back to
    /// the current account for clients that don't match a stored account (mocks).
    /// Also keys the saved live filters, so a delayed callback from an outgoing
    /// view can't save the old account's filters under the newly selected
    /// account (#1199).
    var owningAccountID: UUID? {
        (accounts.account(matching: client) ?? accounts.currentAccount)?.id
    }
}
