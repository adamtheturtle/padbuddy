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
    /// Writes a freshly fetched standalone/detail pad through every cache side effect.
    /// Declines when no complete list exists so one detail row is never represented as
    /// the account's authoritative entire pad list.
    func updatePad(_ pad: Pad, account: UUID, via client: CoderPadClient) {
        guard let updated = PadCacheMutation.replacing(pad, in: get(account)) else { return }

        set(account, pads: updated, via: client)
    }
}
