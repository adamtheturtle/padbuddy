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

        let selection = historyRequestSelection(for: environments)
        let requests = selection.requests
        historyLoadWasTruncated = selection.wasTruncated
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
            histories = loaded.histories
            historyLoadFailures = failures
            historyLoadWasTruncated = selection.wasTruncated || loaded.wasTruncated
        }
    }

    private func replayHistories(
        _ fetchedByIndex: [Int: PadHistory],
        requests: [PadHistoryRequest]
    ) async -> (histories: [PadFileHistory], wasTruncated: Bool) {
        // Build one file at a time off the main actor. Retained results share one
        // pad-wide budget; concurrency cannot multiply the per-file checkpoint cap.
        var budget = PadHistoryLoadBudget()
        var retained: [PadFileHistory] = []
        var wasTruncated = false
        for index in fetchedByIndex.keys.sorted() {
            guard !Task.isCancelled, let history = fetchedByIndex[index] else { break }

            let request = requests[index]
            let file = await PadFileHistory.replaying(id: request.url, title: request.title,
                                                      language: request.language, history: history)
            if budget.admit(file) {
                retained.append(file)
                wasTruncated = wasTruncated || file.wasTruncated
            } else {
                wasTruncated = true
            }
        }
        return (retained, wasTruncated)
    }
}
