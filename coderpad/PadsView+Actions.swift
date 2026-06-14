//
//  PadsView+Actions.swift
//  coderpad
//

import SwiftUI

extension PadsView {
    var bulkConfirmTitle: String {
        switch bulkAction {
        case .endStarted: "End \(PadListLogic.startedPads(in: filtered).count) started pads?"
        case .makePrivate: "Make \(PadListLogic.nonPrivatePads(in: filtered).count) pads private?"
        case nil: ""
        }
    }

    func bulkConfirmButton(_ action: BulkPadAction) -> String {
        switch action {
        case .endStarted: "End Started Pads"
        case .makePrivate: "Make Private"
        }
    }

    func bulkConfirmMessage(_ action: BulkPadAction) -> String {
        switch action {
        case .endStarted:
            "This ends every started pad currently shown in the list. Ending an interview can't be undone."
        case .makePrivate:
            "This marks every pad currently shown in the list as private."
        }
    }

    /// Runs a bulk action over the currently-visible pads, then refreshes. Failures
    /// are counted and surfaced without aborting the rest of the batch.
    func performBulk(_ action: BulkPadAction) async {
        let targets: [Pad] = switch action {
        case .endStarted: PadListLogic.startedPads(in: filtered)
        case .makePrivate: PadListLogic.nonPrivatePads(in: filtered)
        }
        guard !targets.isEmpty else { return }
        isBulkRunning = true
        defer { isBulkRunning = false }
        var failures = 0
        for pad in targets {
            do {
                switch action {
                case .endStarted: try await client.endPad(id: pad.id)
                case .makePrivate: _ = try await client.updatePad(PadUpdate(id: pad.id, isPrivate: true))
                }
            } catch {
                failures += 1
            }
        }
        if failures > 0 {
            bulkError = "\(failures) of \(targets.count) pads couldn't be updated."
        }
        await reload()
    }

    /// Delete a pad reached via swipe action. Broadcasts via `AppRouter.padDeleted`
    /// so this list — and any other open window — drops the row, matching the detail
    /// view's own delete path.
    func deletePad(_ pad: Pad) async {
        do {
            try await client.deletePad(id: pad.id)
            AppRouter.padDeleted(id: pad.id)
        } catch {
            deleteError = error.localizedDescription
        }
    }

    /// Applies any request queued by `AppNavigation` (e.g. from clicking a user in
    /// Organization), then clears it so it isn't re-applied. Runs both on first
    /// appear — covering the case where this pane wasn't mounted when the request
    /// was made — and on change, for when the pane is already on screen.
    func applyPendingRequest() {
        guard let request = nav.padsRequest else { return }
        nav.padsRequest = nil
        // Apply a saved search first so any explicit owner/search below can still
        // override a single field of it when a request carries both.
        if let saved = request.applySearch { apply(saved) }
        if let owner = request.ownerEmail { ownerFilter = owner }
        if let query = request.search { search = query }
        if request.startCreating {
            seedQuestionID = request.seedQuestionID
            showCreate = true
        }
    }

    /// A sparkle button that fills the name field with an on-device suggestion
    /// built from the active filters. Shown only when the model is available; the
    /// field stays fully editable and the user opts in per save.
    var suggestNameButton: some View {
        Button(action: suggestName) {
            if isSuggestingName {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "sparkles")
            }
        }
        .buttonStyle(.borderless)
        .disabled(isSuggestingName)
        .help("Suggest a name from the current filters")
        .accessibilityLabel("Suggest a name")
    }

    func suggestName() {
        let captured = captureCurrentSearch(named: "")
        isSuggestingName = true
        Task {
            let suggestion = await SavedSearchNamer.suggestName(for: captured)
            isSuggestingName = false
            if let suggestion { saveSearchName = suggestion }
        }
    }

    /// Interprets the typed query on device and, when it maps to a real filter set,
    /// applies it and closes the sheet. A query the model can't turn into any
    /// filter leaves the list untouched and surfaces a gentle hint in the sheet.
    func applySmartFilter() async {
        let query = smartFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        isInterpreting = true
        smartFilterFailed = false
        defer { isInterpreting = false }
        let owners = availableOwners.map {
            SearchInterpreter.OwnerOption(email: $0, name: directory.display($0))
        }
        let result = await SearchInterpreter.interpretPads(
            query, languages: availableLanguages, owners: owners, teams: availableTeams
        )
        if let result {
            apply(result)
            showSmartFilter = false
        } else {
            smartFilterFailed = true
        }
    }

    func commitSavedSearch() {
        // Return in the text field fires `onSubmit` and the default-action button can
        // also fire; guarding on the still-open sheet keeps a single keypress from
        // saving the search twice.
        guard showSaveSearch else { return }
        let trimmed = String(saveSearchName.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(NamedSearch.maxNameLength))
        guard !trimmed.isEmpty, let account = accounts.currentAccountID else { return }
        savedSearches.add(captureCurrentSearch(named: trimmed), account: account, kind: .pads)
        showSaveSearch = false
    }

    func apply(_ saved: NamedSearch) {
        search = saved.search
        stateFilter = saved.stateFilter
        languageFilter = saved.languageFilter
        ownerFilter = saved.ownerFilter
        teamFilter = saved.teamFilter
        typeFilter = saved.typeFilter
        updatedWindow = saved.updatedWindow ?? PadDateWindow()
        createdWindow = saved.createdWindow ?? PadDateWindow()
    }

    /// Whether the list's live filters exactly match `saved`, so its chip can show
    /// as active. This is the inverse of `apply` — every field it sets is compared
    /// here — which keeps the highlight honest the instant any filter is changed.
    func isActiveSearch(_ saved: NamedSearch) -> Bool {
        search == saved.search &&
            stateFilter == saved.stateFilter &&
            languageFilter == saved.languageFilter &&
            ownerFilter == saved.ownerFilter &&
            teamFilter == saved.teamFilter &&
            typeFilter == saved.typeFilter &&
            updatedWindow == (saved.updatedWindow ?? PadDateWindow()) &&
            createdWindow == (saved.createdWindow ?? PadDateWindow())
    }

    func captureCurrentSearch(named name: String) -> NamedSearch {
        NamedSearch(
            name: name, search: search,
            stateFilter: stateFilter, languageFilter: languageFilter,
            ownerFilter: ownerFilter, teamFilter: teamFilter,
            typeFilter: typeFilter,
            updatedWindow: updatedWindow.isActive ? updatedWindow : nil,
            createdWindow: createdWindow.isActive ? createdWindow : nil
        )
    }

    // MARK: - Live filter persistence

    /// A change-detection token for the live filters, so they can be re-persisted
    /// the instant any one of them changes without observing each `@State` var.
    var filterSignature: String {
        ([search, stateFilter?.rawValue, languageFilter, ownerFilter, teamFilter, typeFilter]
            .map { $0 ?? "·" }
            + [Self.windowToken(updatedWindow), Self.windowToken(createdWindow)])
            .joined(separator: "|")
    }

    private static func windowToken(_ window: PadDateWindow) -> String {
        window.signatureToken
    }

    static func liveFilterKey(_ account: UUID) -> String {
        "pads.liveFilter.\(account.uuidString)"
    }

    /// Persist the current live filters for the signed-in account, so the list
    /// reopens with the same view next launch. Scoped per account because owners,
    /// teams, and languages are all org-specific. Skipped until the initial restore
    /// has run, so the empty startup state never clobbers a saved snapshot.
    func persistFilters() {
        guard didRestoreFilters, let account = accounts.currentAccountID else { return }
        if let data = try? JSONEncoder().encode(captureCurrentSearch(named: "")) {
            UserDefaults.standard.set(data, forKey: Self.liveFilterKey(account))
        }
    }

    /// Publish the live filter signature for the sidebar to match against the
    /// suggested and saved rows. Unguarded by `didRestoreFilters`/account, since the
    /// sidebar should reflect even the empty starting filter.
    func publishLiveFilter() {
        nav.padsFilter = captureCurrentSearch(named: "")
    }

    /// Restore the persisted live filters for the current account, once. A deep-link
    /// request (handled by `applyPendingRequest`) is applied afterward so it always
    /// wins over a restored snapshot.
    func restoreFilters() {
        guard let account = accounts.currentAccountID else { return }
        didRestoreFilters = true
        guard let data = UserDefaults.standard.data(forKey: Self.liveFilterKey(account)),
              let snapshot = try? JSONDecoder().decode(NamedSearch.self, from: data) else { return }
        apply(snapshot)
    }

    /// Re-restore for a newly selected account: clear the previous account's filters
    /// (they're meaningless against a different org) then load that account's own.
    func restoreFiltersForAccountChange() {
        didRestoreFilters = false
        search = ""
        clearAllFilters()
        restoreFilters()
    }

    // MARK: - Reload

    func reload() async {
        guard !client.apiKey.isEmpty else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            // Render page 1 the moment it lands, then keep growing the list as the
            // remaining pages stream in. Snapshots arrive sorted updated_at,desc from the
            // server, so each one only appends below — no reshuffle as the list fills in.
            let isInitialLoad = pads.isEmpty
            var fetched: [Pad] = []
            for try await snapshot in client.listPadsIncrementally() {
                // The first snapshot is page 1 — the most-recently-updated pads, already
                // usable. Drop the blocking spinner now and let the rest stream in
                // silently behind the already-visible list, rather than spinning until
                // the last page lands.
                if isLoading {
                    isLoading = false
                }
                fetched = snapshot
                // Paint progressively on the first load; on a refresh keep the current
                // list until the full result is in, so a later page failing can't
                // transiently shrink the visible list to just page 1.
                if isInitialLoad {
                    pads = snapshot
                }
            }
            pads = fetched
            finalize(fetched: fetched)
        } catch {
            self.error = error
        }
    }

    /// Records the activity diff, refreshes the per-pad timestamp snapshot, and
    /// caches the full result. Split out of `reload` so the streaming loop stays
    /// the focus there and the diff bookkeeping is testable in isolation.
    func finalize(fetched: [Pad]) {
        let changes = changedPadIDs(in: fetched)
        PadActivityMonitor.shared.record(changedCount: changes.count)
        previousUpdatedAt = timestampSnapshot(of: fetched)
        if let id = accounts.currentAccountID {
            cache.set(id, pads: fetched)
        }
        hasLoadedOnce = true
    }

    /// The ids of pads that are new or whose `updatedAt` advanced since the last
    /// sweep. Empty until the first load completes, so a cold start doesn't flag
    /// every pad as freshly changed.
    func changedPadIDs(in fetched: [Pad]) -> Set<String> {
        guard hasLoadedOnce else { return [] }
        var changes: Set<String> = []
        for pad in fetched {
            guard let prev = previousUpdatedAt[pad.id] else {
                changes.insert(pad.id)
                continue
            }
            if let updated = pad.updatedAt, updated > prev {
                changes.insert(pad.id)
            }
        }
        return changes
    }

    /// A snapshot of each pad's `updatedAt`, used to diff the next sweep.
    func timestampSnapshot(of fetched: [Pad]) -> [String: Date] {
        var state: [String: Date] = [:]
        for pad in fetched {
            if let updated = pad.updatedAt { state[pad.id] = updated }
        }
        return state
    }
}
