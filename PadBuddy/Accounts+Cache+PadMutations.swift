//
//  Accounts+Cache+PadMutations.swift
//  coderpad
//

import Foundation

enum PadCacheMutation {
    /// Returns the patched complete list, or nil when there is no authoritative list
    /// to patch or the cached row is already current.
    static func replacing(_ pad: Pad, in pads: [Pad]) -> [Pad]? {
        guard !pads.isEmpty else { return nil }

        var updated = pads
        let matches = updated.indices.filter { updated[$0].id == pad.id }
        if matches.isEmpty {
            updated.append(pad)
        } else {
            guard matches.contains(where: { updated[$0] != pad }) else { return nil }

            for index in matches {
                updated[index] = pad
            }
        }
        return updated
    }
}

extension PadsCacheStore {
    /// Removes one pad only when the deletion came from the account's current
    /// client. This protects a rekeyed backend reusing the same account UUID from
    /// stale cache, widget, badge, and Spotlight side effects (#1446).
    @discardableResult
    func removePad(
        id padID: String, account accountID: UUID, via clientIdentity: ClientTaskIdentity
    ) -> Bool {
        guard let account = AccountsStore.shared.accounts.first(where: { $0.id == accountID }) else {
            remove(accountID)
            return true
        }

        let client = account.makeClient()
        guard client.taskIdentity == clientIdentity else { return false }

        let pads = get(accountID)
        guard pads.contains(where: { $0.id == padID }) else {
            SpotlightIndexer.removePad(id: padID, account: accountID)
            return true
        }

        set(accountID, pads: pads.filter { $0.id != padID }, via: client)
        return true
    }

    /// Writes a freshly fetched standalone/detail pad through every cache side effect.
    /// Declines when no complete list exists so one detail row is never represented as
    /// the account's authoritative entire pad list.
    func updatePad(_ pad: Pad, account: UUID, via client: CoderPadClient) {
        guard let updated = PadCacheMutation.replacing(pad, in: get(account)) else { return }

        set(account, pads: updated, via: client)
    }
}
