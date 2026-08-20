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
        //
        // Keyed by first-wins rather than `uniqueKeysWithValues` (#2066): the target
        // list comes from the account store, and a duplicated account record would
        // otherwise trap the whole warm at runtime. Duplicates name the same account,
        // so keeping the first entry loses nothing. Begin load once per UUID so a
        // duplicate cannot advance (and later orphan) a second write token.
        var tokens: [UUID: Int] = [:]
        for target in targets {
            guard tokens[target.id] == nil else { continue }
            if let token = PadsCacheStore.shared.beginLoad(target.id, via: target.client) {
                tokens[target.id] = token
            }
        }
        await withTaskGroup(of: (UUID, [Pad]?).self) { group in
            var iterator = targets.makeIterator()
            func addNext() {
                guard let target = iterator.next() else { return }

                group.addTask {
                    do {
                        let pads = try await APIReadCoordinator.shared.pads(
                            accountID: target.id, client: target.client
                        )
                        await NavigationPrefetchHealth.clear(account: target.id, kind: .pads)
                        return (target.id, pads)
                    } catch {
                        // Logged, not swallowed: a quietly incomplete warm should be
                        // diagnosable from Console (#1838); the merged views surface
                        // their own per-account errors on their real loads.
                        logPrefetchFailure("merged pads", account: target.id, error: error)
                        await NavigationPrefetchHealth.record(error, account: target.id, kind: .pads)
                        return (target.id, nil)
                    }
                }
            }
            for _ in 0 ..< mergedPrefetchWidth {
                addNext()
            }

            let clientsByID = Dictionary(targets.map { ($0.id, $0.client) }, uniquingKeysWith: { first, _ in first })
            let session = currentSession
            for await (id, pads) in group {
                // The account or combined-view flag can change mid-fan-out: stop
                // starting requests and stop publishing for a session the user has
                // already left (#2068).
                guard session == currentSession else {
                    group.cancelAll()
                    break
                }

                addNext()
                if let pads, let client = clientsByID[id], let token = tokens[id] {
                    PadsCacheStore.shared.set(id, pads: pads, via: client, accepting: token)
                }
            }
        }
    }

    static func prefetchMergedQuestions(_ targets: [(id: UUID, client: CoderPadClient)]) async {
        // See prefetchMergedPads for the write-token rationale (#1242) and duplicate-ID
        // coalescing (#2066).
        var tokens: [UUID: Int] = [:]
        for target in targets {
            guard tokens[target.id] == nil else { continue }
            if let token = QuestionsCacheStore.shared.beginLoad(target.id, via: target.client) {
                tokens[target.id] = token
            }
        }
        await withTaskGroup(of: (UUID, [Question]?).self) { group in
            var iterator = targets.makeIterator()
            func addNext() {
                guard let target = iterator.next() else { return }

                group.addTask {
                    do {
                        let questions = try await APIReadCoordinator.shared.questions(
                            accountID: target.id, client: target.client
                        )
                        await NavigationPrefetchHealth.clear(account: target.id, kind: .questions)
                        return (target.id, questions)
                    } catch {
                        logPrefetchFailure("merged questions", account: target.id, error: error)
                        await NavigationPrefetchHealth.record(error, account: target.id, kind: .questions)
                        return (target.id, nil)
                    }
                }
            }
            for _ in 0 ..< mergedPrefetchWidth {
                addNext()
            }

            let clientsByID = Dictionary(targets.map { ($0.id, $0.client) }, uniquingKeysWith: { first, _ in first })
            let session = currentSession
            for await (id, questions) in group {
                // See prefetchMergedPads for the session check (#2068).
                guard session == currentSession else {
                    group.cancelAll()
                    break
                }

                addNext()
                if let questions, let client = clientsByID[id], let token = tokens[id] {
                    QuestionsCacheStore.shared.set(id, questions: questions, via: client, accepting: token)
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
                        await NavigationPrefetchHealth.clear(account: target.id, kind: .quota)
                        return (target.id, quota)
                    } catch {
                        logPrefetchFailure("merged quota", account: target.id, error: error)
                        await NavigationPrefetchHealth.record(error, account: target.id, kind: .quota)
                        return (target.id, nil)
                    }
                }
            }
            for _ in 0 ..< mergedPrefetchWidth {
                addNext()
            }

            let clientsByID = Dictionary(targets.map { ($0.id, $0.client) }, uniquingKeysWith: { first, _ in first })
            let session = currentSession
            for await (id, quota) in group {
                // See prefetchMergedPads for the session check (#2068).
                guard session == currentSession else {
                    group.cancelAll()
                    break
                }

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
