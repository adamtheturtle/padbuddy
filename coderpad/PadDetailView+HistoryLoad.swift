//
//  PadDetailView+HistoryLoad.swift
//  coderpad
//

extension PadDetailView {
    // swiftlint:disable:next function_body_length
    func loadHistories(
        for environments: [PadEnvironment], generation: Int, identity: PadDetailLoadIdentity
    ) async {
        guard isCurrentLoad(generation, identity: identity) else { return }

        let requests = historyRequests(for: environments)
        guard !requests.isEmpty else {
            histories = []
            historyLoadFailures = 0
            isLoadingHistory = false
            return
        }

        isLoadingHistory = true
        defer { publishIfCurrent(generation, identity: identity) { isLoadingHistory = false } }
        let client = client
        func fetch(_ request: PadHistoryRequest) async -> (history: PadFileHistory?, failed: Bool) {
            do {
                let history = try await PadHistoryFetcher.fetch(
                    request.url,
                    client: client,
                    usesMockTransport: usesMockHistoryTransport
                )
                guard !history.isEmpty else { return (nil, false) }

                return await (PadFileHistory.replaying(
                    id: request.url, title: request.title, language: request.language, history: history
                ), false)
            } catch let error as PadHistoryFetcher.FetchError where error.isOptionalMissingHistory {
                return (nil, false)
            } catch {
                return (nil, true)
            }
        }

        let (loaded, failures) = await withTaskGroup(
            of: (history: PadFileHistory?, failed: Bool).self
        ) { group in
            let width = 4
            var iterator = requests.makeIterator()
            for _ in 0 ..< width {
                guard let request = iterator.next() else { break }

                group.addTask { await fetch(request) }
            }
            var collected: [PadFileHistory] = []
            var failed = 0
            for await result in group {
                if let history = result.history { collected.append(history) }
                if result.failed { failed += 1 }
                if let request = iterator.next() { group.addTask { await fetch(request) } }
            }
            return (collected, failed)
        }
        publishIfCurrent(generation, identity: identity) {
            let order = Dictionary(uniqueKeysWithValues: requests.enumerated().map { ($1.url, $0) })
            histories = loaded.sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
            historyLoadFailures = failures
        }
    }
}
