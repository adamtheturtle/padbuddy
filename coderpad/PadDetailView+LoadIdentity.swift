//
//  PadDetailView+LoadIdentity.swift
//  coderpad
//

extension PadDetailView {
    func beginLoad(_ identity: PadDetailLoadIdentity, showsRefreshControls: Bool) -> Int? {
        guard !isRefreshing || refreshingIdentity != identity else {
            if showsRefreshControls { self.showsRefreshControls = true }
            return nil
        }

        loadGeneration &+= 1
        refreshingIdentity = identity
        isRefreshing = true
        self.showsRefreshControls = showsRefreshControls
        return loadGeneration
    }

    var detailLoadIdentity: PadDetailLoadIdentity {
        PadDetailLoadIdentity(
            padID: pad.id,
            accountID: accounts.account(matching: client)?.id,
            clientIdentity: client.taskIdentity
        )
    }

    func isCurrentLoad(_ generation: Int, identity: PadDetailLoadIdentity) -> Bool {
        PadDetailLoadIdentity.isCurrent(
            generation: generation,
            currentGeneration: loadGeneration,
            requested: identity,
            current: detailLoadIdentity,
            isCancelled: Task.isCancelled
        )
    }

    func publishIfCurrent(
        _ generation: Int, identity: PadDetailLoadIdentity, _ publication: () -> Void
    ) {
        guard isCurrentLoad(generation, identity: identity) else { return }

        publication()
    }
}
