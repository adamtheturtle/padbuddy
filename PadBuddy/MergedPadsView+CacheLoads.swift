//
//  MergedPadsView+CacheLoads.swift
//  coderpad
//

import Foundation

extension MergedPadsView {
    func cacheLoadContext(
        _ targets: [(id: UUID, client: CoderPadClient)]
    ) -> (clients: [UUID: CoderPadClient], loads: [UUID: Int]) {
        // First target wins for duplicate account IDs (#4540). Beginning a second load
        // for the same UUID would both trap and discard an earlier write token.
        let clients = Dictionary(targets.map { ($0.id, $0.client) }, uniquingKeysWith: { first, _ in first })
        var loads: [UUID: Int] = [:]
        for target in targets {
            guard loads[target.id] == nil else { continue }
            if let token = cache.beginLoad(target.id, via: target.client) {
                loads[target.id] = token
            }
        }
        return (clients, loads)
    }
}
