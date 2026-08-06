//
//  ScreenSectionView+LoadIdentity.swift
//  coderpad
//

extension ScreenCampaignsView {
    static func isCurrentLoad(
        _ generation: Int,
        currentGeneration: Int,
        requestedClientIdentity: ClientTaskIdentity,
        currentClientIdentity: ClientTaskIdentity
    ) -> Bool {
        generation == currentGeneration && requestedClientIdentity == currentClientIdentity
    }
}
