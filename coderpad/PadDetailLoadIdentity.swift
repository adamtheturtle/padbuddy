//
//  PadDetailLoadIdentity.swift
//  coderpad
//

import Foundation

struct PadDetailLoadIdentity: Hashable {
    let padID: String
    let accountID: UUID?
    let clientIdentity: ClientTaskIdentity

    nonisolated static func isCurrent(
        generation: Int, currentGeneration: Int,
        requested: Self, current: Self,
        isCancelled: Bool = false
    ) -> Bool {
        !isCancelled && generation == currentGeneration && requested == current
    }
}
