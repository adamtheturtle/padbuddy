//
//  MergedPadsView+CacheLoads.swift
//  coderpad
//

import Foundation

extension MergedPadsView {
    func cacheLoadContext(
        _ targets: [(id: UUID, client: CoderPadClient)]
    ) -> (clients: [UUID: CoderPadClient], loads: [UUID: Int]) {
        let clients = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0.client) })
        let loads = Dictionary(uniqueKeysWithValues: targets.compactMap { target in
            cache.beginLoad(target.id, via: target.client).map { (target.id, $0) }
        })
        return (clients, loads)
    }
}
