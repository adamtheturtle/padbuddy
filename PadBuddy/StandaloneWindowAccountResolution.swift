//
//  StandaloneWindowAccountResolution.swift
//  coderpad
//

import Foundation

nonisolated enum StandaloneWindowAccountResolution {
    /// A namespaced restored window cannot fall back to another account. If its
    /// named account was removed, it is unavailable rather than still loading.
    static func isExplicitTargetMissing(_ target: UUID?, accounts: [Account]) -> Bool {
        guard let target else { return false }

        return !accounts.contains { $0.id == target }
    }

    static func accountDisappeared(previous: UUID?, current: UUID?) -> Bool {
        previous != nil && current == nil
    }

    static func shouldCaptureFallback(explicitTarget: UUID?, captured: UUID?, current: UUID?) -> Bool {
        explicitTarget == nil && captured == nil && current != nil
    }
}

struct StandaloneWindowLoadIdentity<Route: Hashable>: Hashable {
    let route: Route?
    let clientIdentity: ClientTaskIdentity?
}
