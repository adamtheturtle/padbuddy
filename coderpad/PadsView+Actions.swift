//
//  PadsView+Actions.swift
//  coderpad
//

import SwiftUI

extension PadsView {
    /// Delete a pad reached via swipe action. Broadcasts via `AppRouter.padDeleted`
    /// so this list — and any other open window — drops the row, matching the detail
    /// view's own delete path.
    func deletePad(_ pad: Pad) async {
        do {
            try await client.deletePad(id: pad.id)
            let owner = accounts.account(matching: client)?.id ?? accounts.currentAccountID
            AppRouter.padDeleted(id: pad.id, account: owner, via: client)
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
        // Apply a suggested search first so any explicit owner/search below can still
        // override a single field of it when a request carries both.
        if let saved = request.applySearch { apply(saved) }
        if let owner = request.ownerEmail { ownerFilter = owner }
        if let query = request.search { search = query }
        // Offline the app is read-only: opening the create sheet would offer a
        // submit that can only fail, so drop the request like the merged view (#1002).
        if request.startCreating, !isReadOnly {
            seedQuestionID = request.seedQuestionID
            createFallbackError = request.createError
            showCreate = true
        }
        // Apply an account-scoped selection only when this list shows that account:
        // the request can outlive an account switch, and pad slugs collide across
        // custom servers, so the bare id must not select another account's pad (#1255).
        if let id = request.selectPadID,
           request.selectPadAccountID == nil || request.selectPadAccountID == accounts.currentAccountID {
            selectPad(id: id)
        }
    }

    /// Whether the loaded list holds this pad, via an id index rebuilt only when the
    /// list itself changes.
    ///
    /// Both callers only needed to know *whether* the row is present, and
    /// `resolvePendingPadSelection` repeats after every load until it turns up — so
    /// the scan over the whole list ran once per page delivered (#2478).
    private func containsPad(_ id: String) -> Bool {
        if padIDIndex.revision != padsRevision {
            padIDIndex = (padsRevision, Set(pads.map(\.id)))
        }
        return padIDIndex.ids.contains(id)
    }

    /// Selects the pad with `id`, deferring until the list loads it when the favorite
    /// was picked before the pads arrived (e.g. right after a cold launch).
    /// `resolvePendingPadSelection` completes the deferred case.
    func selectPad(id: String) {
        if containsPad(id) {
            selectedIDs = [id]
            // Reveal it: a favorite picked from the sidebar may sit far down the list.
            pendingScrollToID = id
            pendingSelectPadID = nil
        } else {
            pendingSelectPadID = id
        }
    }

    /// Applies a deferred favorite-pad selection once its pad has loaded. A no-op
    /// when nothing is pending, so it's safe to call after every load.
    func resolvePendingPadSelection() {
        guard let id = pendingSelectPadID, containsPad(id) else { return }

        selectedIDs = [id]
        pendingScrollToID = id
        pendingSelectPadID = nil
    }

    func apply(_ saved: NamedSearch) {
        search = saved.search
        stateFilter = saved.stateFilter
        languageFilter = saved.languageFilter
        ownerFilter = saved.ownerFilter
        teamFilter = saved.teamFilter
        // Restored validated: a stale or corrupt type value would otherwise apply
        // as an opaque filter whose only possible result is an empty list (#1652).
        typeFilter = FilterValueValidation.interviewType(saved.typeFilter)
        updatedWindow = saved.updatedWindow ?? DateWindow()
        createdWindow = saved.createdWindow ?? DateWindow()
    }

    /// Whether the list's live filters exactly match `saved`, so its chip can show
    /// as active. This is the inverse of `apply` — every field it sets is compared
    /// here — which keeps the highlight honest the instant any filter is changed.
    func isActiveSearch(_ saved: NamedSearch) -> Bool {
        FilterSignature.make([search, languageFilter, ownerFilter, teamFilter, typeFilter])
            == FilterSignature.make([
                saved.search, saved.languageFilter, saved.ownerFilter, saved.teamFilter, saved.typeFilter
            ]) &&
            stateFilter == saved.stateFilter &&
            updatedWindow == (saved.updatedWindow ?? DateWindow()) &&
            createdWindow == (saved.createdWindow ?? DateWindow())
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

    var hasActiveFilters: Bool {
        let hasSearch = !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasSearch || stateFilter != nil || languageFilter != nil || ownerFilter != nil
            || teamFilter != nil || typeFilter != nil || updatedWindow.isActive || createdWindow.isActive
    }

    /// A change-detection token for the live filters, so they can be re-persisted
    /// the instant any one of them changes without observing each `@State` var.
    var filterSignature: FilterSignature {
        FilterSignature.make([
            search.trimmingCharacters(in: .whitespacesAndNewlines),
            stateFilter?.rawValue,
            languageFilter,
            ownerFilter,
            teamFilter,
            typeFilter,
            updatedWindow.signatureToken,
            createdWindow.signatureToken
        ])
    }

    static func liveFilterKey(_ account: UUID) -> String {
        "pads.liveFilter.\(account.uuidString)"
    }

    /// Persist the current live filters for the signed-in account, so the list
    /// reopens with the same view next launch. Scoped per account because owners,
    /// teams, and languages are all org-specific. Skipped until the initial restore
    /// has run, so the empty startup state never clobbers a saved snapshot. Keyed
    /// by this view's own client-resolved account, not the globally current one: a
    /// delayed onChange callback from an outgoing view can run after an account
    /// switch, and must not save the old view's filters under the new account (#1199).
    func persistFilters() {
        guard didRestoreFilters, let account = owningAccountID else { return }

        // The shared coder, not a fresh one: this fires on every filter change,
        // including each keystroke in the search field (#2104). Matches
        // `MergedPadsView.persistFilters`.
        if let data = try? SharedCoders.encoder.encode(captureCurrentSearch(named: "")) {
            UserDefaults.standard.set(data, forKey: Self.liveFilterKey(account))
        }
    }

    /// Restore the persisted live filters for this view's account, once. A deep-link
    /// request (handled by `applyPendingRequest`) is applied afterward so it always
    /// wins over a restored snapshot. Guarded so a later `onAppear` (tab switch,
    /// window reopen) can't reapply the saved snapshot over filters the user
    /// changed this session (#1638).
    func restoreFilters() {
        guard !didRestoreFilters, let account = owningAccountID else { return }

        didRestoreFilters = true
        guard let data = UserDefaults.standard.data(forKey: Self.liveFilterKey(account)),
              let snapshot = try? SharedCoders.decoder.decode(NamedSearch.self, from: data) else { return }

        apply(snapshot)
    }

    /// Re-restore for a newly selected account: clear the previous account's filters
    /// (they're meaningless against a different org) then load that account's own.
    func restoreFiltersForAccountChange() {
        didRestoreFilters = false
        search = ""
        clearAllFilters()
        restoreFilters()
        // Let the new account restore its own last-open pad once its list loads.
        didRestoreSelection = false
    }

    // MARK: - Reload

    func reload() async {
        guard !client.apiKey.isEmpty else { return }

        // Claim the newest generation; an overlapping older reload stops applying
        // the moment a newer one starts, so its slower result can't replace fresher
        // data (#1201). The owning account is captured before any await: reading
        // currentAccountID after awaiting could store this account's pads under a
        // newly selected account (#1200).
        reloadGeneration &+= 1
        let generation = reloadGeneration
        let owningID = accounts.account(matching: client)?.id ?? accounts.currentAccountID
        let cacheLoad = owningID.flatMap { cache.beginLoad($0, via: client) }

        isLoading = true
        error = nil
        defer { if generation == reloadGeneration { isLoading = false } }
        do {
            guard let fetched = try await streamPads(
                generation: generation, owningID: owningID, cacheLoad: cacheLoad
            ),
                generation == reloadGeneration else { return }

            pads = fetched
            padsRevision += 1
            finalize(fetched: fetched, account: owningID, cacheLoad: cacheLoad)
        } catch {
            guard generation == reloadGeneration else { return }

            self.error = error
        }
    }

    /// Streams the paged pad list, painting progressively on the first load, and
    /// returns the final complete snapshot — or nil when the stream went stale
    /// (superseded generation) or completed without emitting a single snapshot.
    /// The nil-on-empty-stream case matters: replacing a previously loaded list
    /// with the empty default would wipe valid rows and run deletion/activity
    /// bookkeeping over a phantom result (#1203); a genuinely empty org still
    /// emits its (empty) page 1.
    private func streamPads(generation: Int, owningID: UUID?, cacheLoad: Int?) async throws -> [Pad]? {
        // Render page 1 the moment it lands, then keep growing the list as the
        // remaining pages stream in. Snapshots arrive sorted updated_at,desc from the
        // server, so each one only appends below — no reshuffle as the list fills in.
        let isInitialLoad = pads.isEmpty
        var fetched: [Pad]?
        for try await snapshot in client.listPadsIncrementally() {
            guard generation == reloadGeneration else { return nil }

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
                padsRevision += 1
                if let id = owningID, let cacheLoad {
                    cache.set(id, pads: snapshot, via: client, persist: false, accepting: cacheLoad)
                }
            }
        }
        return fetched
    }

    /// Records the activity diff, refreshes the per-pad timestamp snapshot, and
    /// caches the full result under `account` - the id captured when the reload
    /// started, so a mid-reload account switch can't file these pads under the
    /// wrong account (#1200). Split out of `reload` so the streaming loop stays
    /// the focus there and the diff bookkeeping is testable in isolation.
    func finalize(fetched: [Pad], account: UUID?, cacheLoad: Int? = nil) {
        let changes = padChanges(in: fetched)
        PadActivityMonitor.shared.record(changedCount: changes.count)
        // Notify only about pads the current user owns: a background alert about every
        // colleague's pad activity across the org is noise, not signal (#424). The Dock
        // badge keeps counting per its own configurable scope (#399/#400); this only
        // narrows the opt-in Notification Center alerts.
        let owner = accounts.accounts.first(where: { $0.id == account })
        let myChanges = owner.map { owner in
            changes.filter { owner.owns($0.pad.ownerEmail) }
        } ?? []
        PadUpdateNotifier.shared.notify(changes: myChanges, account: owner)
        previousActivity = Self.activitySnapshot(of: fetched)
        if let id = account, accounts.isCurrentClient(client, for: id) {
            cache.set(id, pads: fetched, via: client, accepting: cacheLoad)
            PadOpenedStore.shared.reconcile(account: id, presentPadIDs: Set(fetched.map(\.id)))
        }
        hasLoadedOnce = true
        // Cold start with an empty cache: the list first appears here, so this is the
        // earliest point the saved selection can be resolved. Idempotent (guarded by
        // `didRestoreSelection`), so the per-refresh calls after this are no-ops.
        restoreSelectedPadIfNeeded(loadComplete: true)
        // A sidebar favorite picked before the list loaded takes priority over the
        // restored selection, so resolve it last.
        resolvePendingPadSelection()
    }

    /// The pads that are new or whose `updatedAt` advanced since the last sweep,
    /// each classified into the most meaningful change we can read from the two
    /// snapshots (see `PadChange`). Empty until the first load completes, so a
    /// cold start doesn't flag every pad as freshly changed.
    func padChanges(in fetched: [Pad]) -> [PadChange] {
        guard hasLoadedOnce else { return [] }

        return Self.padChanges(in: fetched, since: previousActivity)
    }

    /// The pure diff behind `padChanges(in:)`, static so the windowless background
    /// refresher can share the exact same classification (#735).
    static func padChanges(in fetched: [Pad], since previousActivity: [String: PadActivitySnapshot]) -> [PadChange] {
        var changes: [PadChange] = []
        for pad in fetched {
            guard let prev = previousActivity[pad.id] else {
                changes.append(PadChange(pad: pad, kind: .new))
                continue
            }

            // A bump counts only when the timestamp moves forward; treat a pad
            // that gained a timestamp it previously lacked as advanced too.
            let advanced: Bool = if let now = pad.updatedAt {
                prev.updatedAt.map { now > $0 } ?? true
            } else {
                false
            }
            guard advanced else { continue }

            changes.append(PadChange(pad: pad, kind: Self.changeKind(for: pad, since: prev)))
        }
        return changes
    }

    /// Attribute a bumped pad to the most notable thing that changed between the
    /// two snapshots: it ending, or someone joining, falling back to a generic
    /// update when neither is detectable.
    static func changeKind(for pad: Pad, since prev: PadActivitySnapshot) -> PadChange.Kind {
        if pad.isEnded, !prev.isEnded {
            return .ended
        }
        if pad.participants.count > prev.participantCount {
            return .participantJoined
        }
        return .updated
    }

    /// A snapshot of the per-pad fields we diff on the next sweep.
    static func activitySnapshot(of fetched: [Pad]) -> [String: PadActivitySnapshot] {
        var state: [String: PadActivitySnapshot] = [:]
        for pad in fetched {
            state[pad.id] = PadActivitySnapshot(
                updatedAt: pad.updatedAt,
                isEnded: pad.isEnded,
                participantCount: pad.participants.count
            )
        }
        return state
    }
}

/// The slice of a pad's state we remember between refreshes so the next refresh
/// can describe what changed (see `padChanges`).
struct PadActivitySnapshot {
    let updatedAt: Date?
    let isEnded: Bool
    let participantCount: Int
}
