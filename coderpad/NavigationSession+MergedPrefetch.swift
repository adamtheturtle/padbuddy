//
//  NavigationSession+MergedPrefetch.swift
//  coderpad
//
//  The All-Accounts warms: one bounded fan-out per inactive section, split from
//  NavigationSession.swift to keep that file within the type-body length limit.
//

import Foundation

extension NavigationSessionLoader {
    /// How many accounts one merged warm fetches at a time: a large account set
    /// must not fan out one request per account all at once (#1834).
    private static let mergedPrefetchWidth = 4

    static func prefetchMergedPads(_ targets: [(id: UUID, client: CoderPadClient)]) async {
        // Per-account write tokens captured before the fetches begin: a slow warm
        // that completes after a fresher (user-initiated) write must not replace
        // it (#1242).
        let tokens = Dictionary(uniqueKeysWithValues: targets.map {
            ($0.id, PadsCacheStore.shared.writeGeneration[$0.id] ?? 0)
        })
        await withTaskGroup(of: (UUID, [Pad]?).self) { group in
            var iterator = targets.makeIterator()
            func addNext() {
                guard let target = iterator.next() else { return }

                group.addTask {
                    do {
                        let pads = try await target.client.listPads(sort: "updated_at,desc")
                        return (target.id, pads)
                    } catch {
                        // Logged, not swallowed: a quietly incomplete warm should be
                        // diagnosable from Console (#1838); the merged views surface
                        // their own per-account errors on their real loads.
                        logPrefetchFailure("merged pads", account: target.id, error: error)
                        return (target.id, nil)
                    }
                }
            }
            for _ in 0 ..< mergedPrefetchWidth {
                addNext()
            }

            let clientsByID = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0.client) })
            for await (id, pads) in group {
                addNext()
                if let pads, let client = clientsByID[id],
                   (PadsCacheStore.shared.writeGeneration[id] ?? 0) == tokens[id] {
                    PadsCacheStore.shared.set(id, pads: pads, via: client)
                }
            }
        }
    }

    static func prefetchMergedQuestions(_ targets: [(id: UUID, client: CoderPadClient)]) async {
        // See prefetchMergedPads for the write-token rationale (#1242).
        let tokens = Dictionary(uniqueKeysWithValues: targets.map {
            ($0.id, QuestionsCacheStore.shared.writeGeneration[$0.id] ?? 0)
        })
        await withTaskGroup(of: (UUID, [Question]?).self) { group in
            var iterator = targets.makeIterator()
            func addNext() {
                guard let target = iterator.next() else { return }

                group.addTask {
                    do {
                        let questions = try await target.client.listQuestions(sort: "updated_at,desc")
                        return (target.id, questions)
                    } catch {
                        logPrefetchFailure("merged questions", account: target.id, error: error)
                        return (target.id, nil)
                    }
                }
            }
            for _ in 0 ..< mergedPrefetchWidth {
                addNext()
            }

            let clientsByID = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0.client) })
            for await (id, questions) in group {
                addNext()
                if let questions, let client = clientsByID[id],
                   (QuestionsCacheStore.shared.writeGeneration[id] ?? 0) == tokens[id] {
                    QuestionsCacheStore.shared.set(id, questions: questions, via: client)
                }
            }
        }
    }

    static func prefetchMergedQuota(_ targets: [(id: UUID, client: CoderPadClient)]) async {
        await withTaskGroup(of: (UUID, Quota?).self) { group in
            var iterator = targets.makeIterator()
            func addNext() {
                guard let target = iterator.next() else { return }

                group.addTask {
                    do {
                        let quota = try await target.client.quota()
                        return (target.id, quota)
                    } catch {
                        logPrefetchFailure("merged quota", account: target.id, error: error)
                        return (target.id, nil)
                    }
                }
            }
            for _ in 0 ..< mergedPrefetchWidth {
                addNext()
            }

            let clientsByID = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0.client) })
            for await (id, quota) in group {
                addNext()
                if let quota, let client = clientsByID[id] {
                    QuotaCacheStore.shared.set(id, quota: quota, via: client)
                }
            }
        }
    }

    // Fetches whichever lists aren't currently displayed and stores them in the
    // shared caches. The visible section loads itself, so this skips it to avoid
    // a duplicate request. The pads, questions, and quota warms run concurrently:
    // they hit independent endpoints, and chaining them made the last section's
    // warm wait out both earlier fetches for no reason (#1244).
}
