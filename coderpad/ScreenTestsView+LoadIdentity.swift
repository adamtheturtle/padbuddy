//
//  ScreenTestsView+LoadIdentity.swift
//  coderpad
//

struct ScreenTestsLoadIdentity: Hashable {
    let clientIdentity: ClientTaskIdentity
    let campaignID: Int

    static func isCurrent(
        _ generation: Int,
        currentGeneration: Int,
        requestedClientIdentity: ClientTaskIdentity,
        currentClientIdentity: ClientTaskIdentity
    ) -> Bool {
        generation == currentGeneration && requestedClientIdentity == currentClientIdentity
    }
}
