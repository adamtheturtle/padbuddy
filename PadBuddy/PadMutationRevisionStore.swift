//
//  PadMutationRevisionStore.swift
//  coderpad
//

import Foundation

nonisolated struct PadMutationRevisionStore {
    struct Key: Hashable {
        let accountID: UUID?
        let padID: String
        let clientIdentity: ClientTaskIdentity
    }

    struct Claim: Equatable {
        let key: Key
        let revision: Int
    }

    private var revisions: [Key: Int] = [:]

    mutating func claim(_ key: Key) -> Claim {
        revisions[key, default: 0] &+= 1
        return Claim(key: key, revision: revisions[key, default: 0])
    }

    mutating func invalidate(_ key: Key) {
        revisions[key, default: 0] &+= 1
    }

    func isCurrent(_ claim: Claim) -> Bool {
        revisions[claim.key] == claim.revision
    }
}
