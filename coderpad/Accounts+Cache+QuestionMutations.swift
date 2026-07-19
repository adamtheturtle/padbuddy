//
//  Accounts+Cache+QuestionMutations.swift
//  coderpad
//
//  Single-question write-backs for QuestionsCacheStore, so an edit or a create is
//  reflected on every cache-backed surface (disk snapshot, Spotlight, the New Pad
//  from Question menu, a section re-entry) without waiting for the next full list
//  reload (#1005, #1007). Deletions already had this via `removeQuestion`; these are
//  the missing edit/insert counterparts, built on `get`/`set` so the full `set` side
//  effects run. Split from Accounts+Cache.swift to keep that file focused.
//

import Foundation

extension QuestionsCacheStore {
    /// Whether a question id could have come from CoderPad.
    ///
    /// Ids are positive. A malformed mutation response carrying 0 or a negative id
    /// was written straight into the cache, the disk snapshot, and the Spotlight
    /// index, producing rows that can never be fetched or deleted normally (#2621).
    private func isValidQuestionID(_ id: Int) -> Bool {
        id > 0
    }

    /// Whether this account has a cached list at all.
    ///
    /// A write-back is a *patch* of a known list. With no list, there is nothing to
    /// patch, and writing one row would present a single question to disk, Spotlight,
    /// and every other cache-backed surface as though it were the account's complete
    /// question bank (#2619). Nothing is stale in that state either — those surfaces
    /// show nothing and load fresh — so declining is both safe and correct.
    private func hasListSnapshot(_ account: UUID) -> Bool {
        !get(account).isEmpty
    }

    /// Cache-backed menus need one deterministic order independent of whichever
    /// live list sort a window currently uses. Full fetches request this same
    /// updated-at-descending order; mutations preserve it locally (#1450).
    private func canonicalOrder(_ questions: [Question]) -> [Question] {
        QuestionSort.lastUsedDesc.sorted(questions)
    }

    /// Replaces one question in the account's cached list and re-runs the `set` side
    /// effects.
    ///
    /// `client` must be the client the mutation was actually performed through, so
    /// `set`'s credential check can reject a response that outlived its account's
    /// re-key. Rebuilding a client from the stored account here instead would always
    /// match by construction and defeat that check entirely (#754, #2623).
    ///
    /// A no-op when the account is unknown, no list has been cached yet, the id is
    /// invalid, or the cached rows are already identical (so repeated broadcasts
    /// don't churn Spotlight and disk).
    func updateQuestion(_ question: Question, account: UUID?, via client: CoderPadClient? = nil) {
        guard let account,
              let stored = AccountsStore.shared.accounts.first(where: { $0.id == account }),
              isValidQuestionID(question.id),
              hasListSnapshot(account) else { return }

        var questions = get(account)
        // Every matching row, not just the first. Duplicate ids do turn up (a cache
        // seed overlapping a fresh page), and repairing one left the stale twin
        // visible on cache-backed surfaces and in Spotlight (#2620).
        let matches = questions.indices.filter { questions[$0].id == question.id }
        guard !matches.isEmpty else {
            // The list is loaded but doesn't have this question — a detail view or
            // deep link reached it directly. Add it rather than dropping the edit and
            // leaving every cache-backed surface stale until a full reload (#2618).
            questions.append(question)
            guard let client = provenanceClient(client, stored: stored) else { return }

            set(account, questions: canonicalOrder(questions), via: client)
            return
        }
        guard matches.contains(where: { questions[$0] != question }) else { return }

        for index in matches {
            questions[index] = question
        }
        guard let client = provenanceClient(client, stored: stored) else { return }

        set(account, questions: questions, via: client)
    }

    /// The client a cache write is credential-checked against in `set`.
    ///
    /// A caller that supplies the client its response came from gets a real check: a
    /// re-key while the request was in flight makes it differ from the account's
    /// current client and the write is refused (#754, #2623). A caller with no client —
    /// one applying a router broadcast, which carries the account but not the
    /// credentials it was fetched with — has no provenance to check, so the account's
    /// own client stands in and the guard passes. Those writes are still scoped by
    /// account id; they simply cannot detect an in-flight re-key. Prefer passing the
    /// client wherever it is known.
    private func provenanceClient(_ client: CoderPadClient?, stored: Account) -> CoderPadClient? {
        client ?? stored.makeClient()
    }

    /// Inserts a newly created question into the cache's canonical updated-at order,
    /// so cache-backed surfaces do not inherit an arbitrary active window sort.
    /// Declines when no list has been cached — see `hasListSnapshot`.
    func insertQuestion(_ question: Question, account: UUID?, via client: CoderPadClient? = nil) {
        guard let account,
              let stored = AccountsStore.shared.accounts.first(where: { $0.id == account }),
              isValidQuestionID(question.id),
              hasListSnapshot(account) else { return }

        var questions = get(account)
        questions.removeAll { $0.id == question.id }
        questions.append(question)
        guard let client = provenanceClient(client, stored: stored) else { return }

        set(account, questions: canonicalOrder(questions), via: client)
    }
}
