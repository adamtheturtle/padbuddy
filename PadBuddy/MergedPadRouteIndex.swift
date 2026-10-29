import Foundation

nonisolated enum MergedPadRouteIndex {
    static let maximumRoutes = 10000

    static func build(
        _ sources: some Sequence<(UUID, [Pad])>, maximum: Int = maximumRoutes
    ) -> [String: Set<UUID>] {
        let limit = min(max(0, maximum), maximumRoutes)
        var routes: [String: Set<UUID>] = [:]
        for (account, pads) in sources {
            for pad in pads {
                guard let id = MergedPadIdentity.validated(pad.id) else { continue }

                if var owners = routes[id] {
                    if owners.count < 2 {
                        owners.insert(account)
                        routes[id] = owners
                    }
                } else if routes.count < limit {
                    routes[id] = [account]
                }
            }
        }
        return routes
    }
}
