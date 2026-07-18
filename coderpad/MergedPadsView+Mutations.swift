//
//  MergedPadsView+Mutations.swift
//  coderpad
//
//  In-place row mutations (edit, delete, create) for the combined "All Accounts"
//  pads list, split from MergedPadsView+Logic.swift to keep it under the length
//  lint.
//

import SwiftUI

extension MergedPadsView {
    /// Apply an edited pad to its account's list. `account` is the owning account
    /// from the broadcast; it disambiguates a slug collision across custom servers
    /// (#761). When absent, fall back to the (collision-prone) routing map.
    func applyUpdated(_ pad: Pad, account: UUID? = nil) {
        guard let accountID = account ?? router.padAccountID[pad.id],
              var pads = padsByAccount[accountID],
              let index = pads.firstIndex(where: { $0.id == pad.id }) else { return }

        pads[index] = pad
        padsByAccount[accountID] = pads
        // Pad slugs can collide across custom servers, so also require the edited
        // pad to belong to the account whose pad is routed into the detail pane;
        // an account-less broadcast keeps the old slug-only behavior.
        if selection?.id == pad.id,
           account == nil || router.selectedPadAccountID == nil || router.selectedPadAccountID == accountID {
            selection = pad
        }
    }

    /// Remove a deleted pad. With a known `account`, only that account's copy is
    /// dropped, so a colliding slug on another custom server is left intact
    /// (#761); without it, the route map resolves the owner as before.
    func removePad(id: String, account: UUID? = nil) {
        if let account {
            padsByAccount[account] = padsByAccount[account]?.filter { $0.id != id }
        } else if let accountID = router.padAccountID[id],
                  padsByAccount[accountID]?.contains(where: { $0.id == id }) == true {
            padsByAccount[accountID] = padsByAccount[accountID]?.filter { $0.id != id }
        } else {
            // Fallback when the route map doesn't have the pad yet.
            for (accountID, pads) in padsByAccount where pads.contains(where: { $0.id == id }) {
                padsByAccount[accountID] = pads.filter { $0.id != id }
            }
        }
        publishRoutes()
    }

    /// A pad created outside the lists (widget, menu-bar extra, New Pad from
    /// Question) appears immediately in its account's rows rather than waiting for
    /// the next reload (#1251). Ignored when the broadcast's account isn't one of
    /// the merged accounts.
    func applyCreated(_ creation: PadMutation) {
        guard let accountID = creation.account,
              let account = accounts.mergeableAccounts.first(where: { $0.id == accountID }) else { return }

        insert(creation.pad, into: account)
    }

    /// Insert a just-created pad at the top of its account's rows. A no-op when the
    /// account already holds the pad, so a repeated create notification can't
    /// produce duplicate rows sharing one identity (#1218).
    func insert(_ pad: Pad, into account: Account) {
        var pads = padsByAccount[account.id] ?? []
        guard !pads.contains(where: { $0.id == pad.id }) else { return }

        pads.insert(pad, at: 0)
        padsByAccount[account.id] = pads
        cache.set(account.id, pads: pads, via: account.makeClient())
        publishRoutes()
    }
}
