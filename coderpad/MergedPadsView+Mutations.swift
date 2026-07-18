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
    func applyUpdated(_ pad: Pad) {
        guard let accountID = router.padAccountID[pad.id],
              var pads = padsByAccount[accountID],
              let index = pads.firstIndex(where: { $0.id == pad.id }) else { return }

        pads[index] = pad
        padsByAccount[accountID] = pads
        if selection?.id == pad.id { selection = pad }
    }

    func removePad(id: String) {
        // The deletion broadcast carries only the slug (carrying the account is
        // tracked as #761), so resolve the owning account via the route map and
        // drop the row from just that account rather than scanning and
        // rebuilding every account's array (#368).
        if let accountID = router.padAccountID[id],
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

    func insert(_ pad: Pad, into account: Account) {
        var pads = padsByAccount[account.id] ?? []
        pads.insert(pad, at: 0)
        padsByAccount[account.id] = pads
        cache.set(account.id, pads: pads, via: account.makeClient())
        publishRoutes()
    }
}
