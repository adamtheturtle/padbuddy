//
//  NavigationSession+Prefetch.swift
//  coderpad
//
//  The single-account warms: incremental pad/question paging and the quota fetch,
//  split from NavigationSession.swift to keep that file within the type-body
//  length limit.
//

import Foundation

extension NavigationSessionLoader {
    static func prefetchPads(id: UUID, client: CoderPadClient) async {
        await withWarmClaim("pads:\(id.uuidString)") {
            await performPadsPrefetch(id: id, client: client)
        }
    }

    private static func performPadsPrefetch(id: UUID, client: CoderPadClient) async {
        // Write-token coordination (#1242): every write re-checks that no OTHER
        // writer (a user-initiated reload finishing after this warm began) touched
        // the account since this warm's previous write. When one did, the warm
        // stops writing - the fresher result wins - rather than replacing it.
        // Captured before the first await: a warm must not keep paging for, or
        // publishing into, a session the user has already switched away from (#2068).
        let session = currentSession
        guard let loadGeneration = PadsCacheStore.shared.beginLoad(id, via: client) else { return }

        func writeIfCurrent(_ pads: [Pad], persist: Bool) {
            guard session == currentSession else { return }

            PadsCacheStore.shared.set(
                id, pads: pads, via: client, persist: persist, accepting: loadGeneration
            )
        }

        // Progressive snapshots only warm a COLD cache: replacing an already
        // complete list page by page would leave a truncated list in memory when
        // a later page fails (#1836). A warm cache is replaced only by the final,
        // complete result.
        let hadCompleteList = !PadsCacheStore.shared.cached(id).isEmpty
        var publication = SnapshotPublicationGate()
        var latest: [Pad] = []
        do {
            for try await snapshot in RetainedListStream.bounded(client.listPadsIncrementally()) {
                guard session == currentSession else { return }

                latest = snapshot
                if !hadCompleteList, publication.shouldPublish() {
                    writeIfCurrent(snapshot, persist: false)
                }
            }
            writeIfCurrent(latest, persist: true)
        } catch {
            logPrefetchFailure("pads", account: id, error: error)
            if !hadCompleteList, !latest.isEmpty {
                writeIfCurrent(latest, persist: false)
            }
        }
    }

    static func prefetchQuestions(id: UUID, client: CoderPadClient) async {
        await withWarmClaim("questions:\(id.uuidString)") {
            await performQuestionsPrefetch(id: id, client: client)
        }
    }

    private static func performQuestionsPrefetch(id: UUID, client: CoderPadClient) async {
        // See performPadsPrefetch for the write-token (#1242) and session (#2068)
        // rationale.
        let session = currentSession
        guard let loadGeneration = QuestionsCacheStore.shared.beginLoad(id, via: client) else { return }

        func writeIfCurrent(_ questions: [Question], persist: Bool) {
            guard session == currentSession else { return }

            QuestionsCacheStore.shared.set(
                id, questions: questions, via: client,
                persist: persist, accepting: loadGeneration
            )
        }

        // See performPadsPrefetch: progressive writes only warm a cold cache (#1836).
        let hadCompleteList = !QuestionsCacheStore.shared.cached(id).isEmpty
        var latest: [Question] = []
        do {
            for try await snapshot in RetainedListStream.bounded(client.listQuestionsIncrementally()) {
                guard session == currentSession else { return }

                latest = snapshot
                if !hadCompleteList {
                    writeIfCurrent(snapshot, persist: false)
                }
            }
            writeIfCurrent(latest, persist: true)
        } catch {
            logPrefetchFailure("questions", account: id, error: error)
            if !hadCompleteList, !latest.isEmpty {
                writeIfCurrent(latest, persist: false)
            }
        }
    }

    static func prefetchQuota(id: UUID, client: CoderPadClient) async {
        await withWarmClaim("quota:\(id.uuidString)") {
            let session = currentSession
            do {
                let quota = try await client.quota()
                // See performPadsPrefetch: a result that lands after the session
                // changed is not published (#2068).
                guard session == currentSession else { return }

                QuotaCacheStore.shared.set(id, quota: quota, via: client)
            } catch {
                logPrefetchFailure("quota", account: id, error: error)
            }
        }
    }
}
