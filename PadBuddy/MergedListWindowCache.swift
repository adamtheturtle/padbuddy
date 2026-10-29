import Foundation

@MainActor
final class MergedListWindowCache<Item: Sendable> {
    struct Window {
        let values: [Item]
        let isComplete: Bool
        let coverage: Int
        let identity: ClientTaskIdentity
        let fetchedAt: ContinuousClock.Instant
    }

    private let maximumRecords: Int
    private let isCurrent: @MainActor (UUID, CoderPadClient) -> Bool
    private var identities: [UUID: ClientTaskIdentity] = [:]
    private var windows: [UUID: Window] = [:]

    init(maximumRecords: Int = RetainedListStream.maximumRecords,
         isCurrent: @escaping @MainActor (UUID, CoderPadClient) -> Bool = {
             AccountsStore.shared.isCurrentClient($1, for: $0)
         }) {
        self.maximumRecords = max(0, maximumRecords)
        self.isCurrent = isCurrent
    }

    var recordsPerAccount: Int {
        maximumRecords / max(1, identities.count)
    }

    var retainedCount: Int {
        windows.values.reduce(0) { $0 + $1.values.count }
    }

    func configure(_ targets: [(id: UUID, identity: ClientTaskIdentity)]) {
        let next = Dictionary(targets.map { ($0.id, $0.identity) }, uniquingKeysWith: { first, _ in first })
        guard next != identities else { return }

        identities = next
        let limit = recordsPerAccount
        var retained: [UUID: Window] = [:]
        for (id, window) in windows where identities[id] == window.identity {
            let values = window.values.count <= limit ? window.values : Array(window.values.prefix(limit))
            retained[id] = Window(values: values,
                                  isComplete: window.isComplete && window.values.count <= limit,
                                  coverage: min(window.coverage, limit), identity: window.identity,
                                  fetchedAt: window.fetchedAt)
        }
        windows = retained
    }

    func cached(_ id: UUID, via client: CoderPadClient, freshOnly: Bool = false,
                at now: ContinuousClock.Instant = ContinuousClock.now) -> Window? {
        guard identities[id] == client.taskIdentity, isCurrent(id, client),
              let window = windows[id], window.identity == client.taskIdentity else { return nil }

        if freshOnly {
            let age = window.fetchedAt.duration(to: now)
            guard age >= .zero, age < .seconds(60),
                  window.isComplete || window.coverage >= recordsPerAccount else { return nil }
        }
        return window
    }

    func set(_ values: [Item], account id: UUID, via client: CoderPadClient, requestedLimit: Int,
             at now: ContinuousClock.Instant = ContinuousClock.now) {
        guard identities[id] == client.taskIdentity, isCurrent(id, client) else { return }

        let limit = recordsPerAccount
        windows[id] = Window(values: values.count <= limit ? values : Array(values.prefix(limit)),
                             isComplete: values.count < requestedLimit && values.count <= limit,
                             coverage: min(requestedLimit, limit), identity: client.taskIdentity, fetchedAt: now)
    }

    func remove(_ id: UUID) {
        windows[id] = nil
        identities[id] = nil
    }
}

enum MergedListWindows {
    static let pads = MergedListWindowCache<Pad>()

    static func preparePads() {
        pads.configure(AccountsStore.shared.mergeableAccounts.map {
            (id: $0.id, identity: $0.makeClient().taskIdentity)
        })
    }

    static func readPads(account: UUID, client: CoderPadClient, limit: Int, force: Bool = false) async throws -> [Pad] {
        if !force, let window = pads.cached(account, via: client, freshOnly: true) {
            return window.values
        }

        return try await APIReadCoordinator.shared.pads(
            accountID: account, client: client, force: force, maximumRecords: limit
        )
    }
}
