//
//  PadDetailView+HistoryLoad.swift
//  coderpad
//

import Foundation

nonisolated enum PadHistoryFetchOutcome: Sendable {
    case loaded(PadHistory?)
    case failed
    case cancelled
}

extension PadDetailView {
    // Bounded scheduling, cancellation, and the three fetch outcomes are clearer
    // together than split across stateful callbacks.
    // swiftlint:disable:next function_body_length cyclomatic_complexity
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

        func fetch(_ request: PadHistoryRequest) async -> PadHistoryFetchOutcome {
            do {
                let history = try await client.padHistory(historyURL: request.url)
                return .loaded(history.isEmpty ? nil : history)
            } catch let CoderPadError.http(status, _) where status == 404 || status == 410 {
                return .loaded(nil)
            } catch is CancellationError {
                return .cancelled
            } catch let error as URLError where error.code == .cancelled {
                return .cancelled
            } catch {
                return .failed
            }
        }

        let (fetchedByIndex, failures) = await withTaskGroup(
            of: (index: Int, outcome: PadHistoryFetchOutcome).self
        ) { group in
            var iterator = requests.enumerated().makeIterator()

            func add(_ element: EnumeratedSequence<[PadHistoryRequest]>.Iterator.Element) {
                group.addTask {
                    let outcome = await fetch(element.element)
                    return (element.offset, outcome)
                }
            }

            for _ in 0 ..< fetchWidth {
                guard !Task.isCancelled, let request = iterator.next() else { break }

                add(request)
            }
            var collectedByIndex: [Int: PadHistory] = [:]
            var failed = 0
            for await result in group {
                if case .cancelled = result.outcome {
                    group.cancelAll()
                    continue
                }
                if Task.isCancelled {
                    group.cancelAll()
                    continue
                }
                switch result.outcome {
                case let .loaded(history):
                    if let history {
                        collectedByIndex[result.index] = history
                    }

                case .failed:
                    failed += 1

                case .cancelled:
                    break
                }
                if let request = iterator.next() {
                    add(request)
                }
            }
            return (collectedByIndex, failed)
        }
        guard !Task.isCancelled else { return }

        let loaded = await replayHistories(fetchedByIndex, requests: requests)
        publishIfCurrent(generation, identity: identity) {
            histories = loaded
            historyLoadFailures = failures
        }
    }

    private func replayHistories(
        _ fetchedByIndex: [Int: PadHistory],
        requests: [PadHistoryRequest]
    ) async -> [PadFileHistory] {
        // Bounded like the fetch above, and more tightly, because replay is the
        // expensive half: `PadFileHistory.init` walks up to `maxSnapshotEntries` OT
        // entries, materializes the whole document as `[UInt16]` per entry, and
        // retains checkpoints up to `maxSnapshotBytes` *per file*. Adding a task per
        // fetched history made peak memory the sum of those budgets for a pad that had
        // just been careful to open eight sockets at a time (#4803).
        let replayWidth = 4
        // Sorted so the fan-out is deterministic rather than following dictionary
        // order, which decides which files hold memory at the same moment.
        let pending = fetchedByIndex.sorted { $0.key < $1.key }

        return await withTaskGroup(of: (index: Int, history: PadFileHistory).self) { group in
            var iterator = pending.makeIterator()

            func add(_ element: (key: Int, value: PadHistory)) {
                let request = requests[element.key]
                group.addTask {
                    let replayed = await PadFileHistory.replaying(
                        id: request.url,
                        title: request.title,
                        language: request.language,
                        history: element.value
                    )
                    return (element.key, replayed)
                }
            }

            for _ in 0 ..< replayWidth {
                guard let next = iterator.next() else { break }

                add(next)
            }
            var replayedByIndex: [Int: PadFileHistory] = [:]
            for await result in group {
                replayedByIndex[result.index] = result.history
                if let next = iterator.next() {
                    add(next)
                }
            }
            return requests.indices.compactMap { replayedByIndex[$0] }
        }
    }
}
