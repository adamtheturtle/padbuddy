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

        func fetch(_ request: PadHistoryRequest) async -> (history: PadHistory?, failed: Bool) {
            do {
                let history = try await client.padHistory(historyURL: request.url)
                return (history.isEmpty ? nil : history, false)
            } catch let CoderPadError.http(status, _) where status == 404 || status == 410 {
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
