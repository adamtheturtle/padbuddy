//
//  ContentView+SplitSelection.swift
//  coderpad
//

import SwiftUI

// MARK: - Selection restore (#273) and detail settle (#326)

extension MainSplit {
    /// UserDefaults key for the selected pad/question id, scoped to the current account.
    /// Only the single-account view persists a selection: the combined view's selection
    /// spans accounts and its row identity isn't a stable per-account id, so restoring it
    /// reliably is left for follow-up.
    func selectionKey(_ kind: String) -> String? {
        guard !store.isMergedView, let id = store.currentAccountID else { return nil }

        return "selection.\(id.uuidString).\(kind)"
    }

    /// Changes whenever the active section, or the count of its (lazily disk-loaded)
    /// cache, changes — so the restore re-runs both when the section is restored at
    /// launch and when the list's rows first arrive.
    var restoreProbe: String {
        guard !store.isMergedView, let account = store.currentAccountID else { return "none" }

        let count = section == .questions
            ? questionsCache.get(account).count
            : padsCache.get(account).count
        return "\(account.uuidString):\(section.rawValue):\(count)"
    }

    /// Re-selects the pad/question the user left selected last session, once its row is
    /// available. Runs at most once per section per session and only while nothing is
    /// already selected, so it resumes where the user left off without ever fighting a
    /// fresh selection. Waits (without consuming its one shot) until the list has rows.
    func restoreSelectionIfNeeded() {
        guard !store.isMergedView, let account = store.currentAccountID,
              !restoredSections.contains(section) else { return }

        switch section {
        case .pads:
            guard let key = selectionKey("pad"),
                  let savedID = UserDefaults.standard.string(forKey: key) else {
                restoredSections.insert(section)
                return
            }

            let pads = padsCache.get(account)
            guard !pads.isEmpty else { return }

            if padSelection == nil, let match = pads.first(where: { $0.id == savedID }) {
                padSelection = match
            }
            restoredSections.insert(section)

        case .questions:
            guard let key = selectionKey("question"),
                  let savedID = UserDefaults.standard.object(forKey: key) as? Int else {
                restoredSections.insert(section)
                return
            }

            let questions = questionsCache.get(account)
            guard !questions.isEmpty else { return }

            if questionSelection == nil, let match = questions.first(where: { $0.id == savedID }) {
                questionSelection = match
            }
            restoredSections.insert(section)

        case .organization, .quota:
            break
        }
    }

    /// Persists a non-nil selection so the next launch can resume it. Clears are not
    /// persisted: an account switch nils the selection programmatically, and treating
    /// that as "forget" would wipe the very value we want to restore.
    func persistSelection(padID: String?, questionID: Int?) {
        if let padID, let key = selectionKey("pad") {
            UserDefaults.standard.set(padID, forKey: key)
        }
        if let questionID, let key = selectionKey("question") {
            UserDefaults.standard.set(questionID, forKey: key)
        }
    }

    /// Moves the live pad selection into the detail pane, debouncing only the row-to-row
    /// moves of a *rapid* arrow-key sweep. Appearing (nothing → a row) and clearing (a
    /// row → nothing) apply at once, and so does a deliberate move — a click, or slow
    /// arrowing — because it arrives well after the previous change. Only changes that
    /// follow the last one within the settle window are treated as a sweep and wait it
    /// out (abandoned if the selection changes again first). This keeps single clicks
    /// instant (#395) while still collapsing a fast sweep to its final row (#326).
    func settleDetailPad() async {
        let rapid = registerSelectionChange()
        if detailPad == padSelection { return }
        if detailPad != nil, padSelection != nil, rapid {
            try? await Task.sleep(for: Self.detailSettle)
            if Task.isCancelled { return }
        }
        detailPad = padSelection
    }

    /// The question counterpart to ``settleDetailPad``.
    func settleDetailQuestion() async {
        let rapid = registerSelectionChange()
        if detailQuestion == questionSelection { return }
        if detailQuestion != nil, questionSelection != nil, rapid {
            try? await Task.sleep(for: Self.detailSettle)
            if Task.isCancelled { return }
        }
        detailQuestion = questionSelection
    }

    /// Records this selection change and reports whether it arrived quickly enough after
    /// the previous one to be part of an arrow-key sweep (rather than a deliberate click
    /// or slow navigation, which land after the settle window). See #395.
    func registerSelectionChange() -> Bool {
        let now = Date()
        let rapid = lastDetailChange.map { now.timeIntervalSince($0) < Self.detailSettleSeconds } ?? false
        lastDetailChange = now
        return rapid
    }

    /// Fetches whichever lists aren't currently displayed and stores them in the
    /// shared caches (which also persist to disk). The visible section loads itself,
    /// so we skip it here to avoid a duplicate request.
    func prefetchInactiveSections(account: Account, active: AppSection) async {
        guard account.isMock || !account.apiKey.isEmpty else { return }

        let client = account.makeClient()
        let id = account.id
        // Stream pages so the cache is warm from page 1 — the first switch shows the
        // top (most-recently-updated) pads immediately while the rest fill in behind it,
        // instead of waiting for every page of a large org to land.
        if active != .pads {
            var latest: [Pad] = []
            do {
                for try await snapshot in client.listPadsIncrementally() {
                    latest = snapshot
                    // Warm memory per page (cheap); persist the final list once below.
                    PadsCacheStore.shared.set(id, pads: snapshot, persist: false)
                }
                PadsCacheStore.shared.set(id, pads: latest)
            } catch {
                // Partial results still warm the UI; persist whatever arrived.
                if !latest.isEmpty { PadsCacheStore.shared.set(id, pads: latest) }
            }
        }
        if active != .questions, let questions = try? await client.listQuestions(sort: "updated_at,desc") {
            QuestionsCacheStore.shared.set(id, questions: questions)
        }
        // Warm the quota too, so the sidebar knows up front whether the plan is
        // unlimited (and hides the unreachable Quota page) without the user having to
        // open Quota or Organization first. See #306.
        if let quota = try? await client.quota() {
            QuotaCacheStore.shared.set(id, quota: quota)
        }
    }
}
