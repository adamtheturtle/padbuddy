//
//  PadDetailView+HistoryLoad.swift
//  coderpad
//

import Foundation

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
        let fetchWidth = 8
        let session: URLSession? = if usesMockHistoryTransport {
            nil
        } else {
            URLSession(
                configuration: Self.historySessionConfiguration(fetchWidth: fetchWidth),
                delegate: PadHistoryRedirectDelegate(accountBaseURL: client.baseURL),
                delegateQueue: nil
            )
        }
        defer { session?.finishTasksAndInvalidate() }

        func fetch(_ request: PadHistoryRequest) async -> (history: PadHistory?, failed: Bool) {
            do {
                let history = try await PadHistoryFetcher.fetch(
                    request.url,
                    client: client,
                    usesMockTransport: usesMockHistoryTransport,
                    session: session
                )
                return (history.isEmpty ? nil : history, false)
            } catch let error as PadHistoryFetcher.FetchError where error.isOptionalMissingHistory {
                return (nil, false)
            } catch {
                return (nil, true)
            }
        }

        let (fetchedByIndex, failures) = await withTaskGroup(
            of: (index: Int, history: PadHistory?, failed: Bool).self
        ) { group in
            var iterator = requests.enumerated().makeIterator()

            func add(_ element: EnumeratedSequence<[PadHistoryRequest]>.Iterator.Element) {
                group.addTask {
                    let result = await fetch(element.element)
                    return (element.offset, result.history, result.failed)
                }
            }

            for _ in 0 ..< fetchWidth {
                guard let request = iterator.next() else { break }

                add(request)
            }
            var collectedByIndex: [Int: PadHistory] = [:]
            var failed = 0
            for await result in group {
                if let history = result.history {
                    collectedByIndex[result.index] = history
                }
                if result.failed {
                    failed += 1
                }
                if let request = iterator.next() {
                    add(request)
                }
            }
            return (collectedByIndex, failed)
        }
        let loaded = await replayHistories(fetchedByIndex, requests: requests)
        publishIfCurrent(generation, identity: identity) {
            histories = loaded
            historyLoadFailures = failures
        }
    }

    private static func historySessionConfiguration(fetchWidth: Int) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpMaximumConnectionsPerHost = fetchWidth
        return configuration
    }

    private func replayHistories(
        _ fetchedByIndex: [Int: PadHistory],
        requests: [PadHistoryRequest]
    ) async -> [PadFileHistory] {
        await withTaskGroup(of: (index: Int, history: PadFileHistory).self) { group in
            for (index, history) in fetchedByIndex {
                let request = requests[index]
                group.addTask {
                    let replayed = await PadFileHistory.replaying(
                        id: request.url,
                        title: request.title,
                        language: request.language,
                        history: history
                    )
                    return (index, replayed)
                }
            }

            var replayedByIndex: [Int: PadFileHistory] = [:]
            for await result in group {
                replayedByIndex[result.index] = result.history
            }
            return requests.indices.compactMap { replayedByIndex[$0] }
        }
    }
}
