//
//  MergedPadsView+Logic.swift
//  coderpad
//
//  Data, filtering, fan-out refresh, and per-account-routed actions for the
//  combined "All Accounts" pads list.
//

import AppKit
import SwiftUI

extension MergedPadsView {
    // MARK: - Combined + filtered data

    /// Every account's pads, tagged with their source account and sorted newest
    /// first. Read many times in one render (the filter pass, each filter chip's
    /// option list, the result count, the empty-state checks), so it's memoized
    /// into `scopedCache` once per render by `refreshScoped()`. Recomputing the
    /// cross-account sort on every read beach-balled the main thread on large
    /// merged orgs — most visibly when toggling a preset like "Mine", which fires
    /// several re-renders in quick succession.
    var scoped: [AccountScoped<Pad>] {
        scopedCache.rows
    }

    /// Rebuild the memoized `scoped` rows for one render. Mirrors `refreshFiltered`
    /// (and `PadsView`'s `filtered` memo): a reference-type cache so `body` can
    /// refresh it without mutating SwiftUI state mid-evaluation. Reads only
    /// `padsByAccount` (seeded from cache, then refreshed) so it never triggers a
    /// cache read.
    func refreshScoped() {
        var rows: [AccountScoped<Pad>] = []
        for account in accounts.mergeableAccounts {
            for pad in padsByAccount[account.id] ?? [] {
                rows.append(AccountScoped(account: account, item: pad, id: pad.id))
            }
        }
        scopedCache.rows = rows.sorted {
            ($0.item.updatedAt ?? $0.item.createdAt ?? .distantPast)
                > ($1.item.updatedAt ?? $1.item.createdAt ?? .distantPast)
        }
    }

    var filtered: [AccountScoped<Pad>] {
        filteredCache.rows
    }

    func refreshFiltered() {
        let criteria = PadFilterCriteria(
            search: search, state: stateFilter, language: languageFilter,
            owner: ownerFilter, team: nil, type: typeFilter,
            updated: updatedWindow, created: createdWindow
        )
        let now = Date()
        filteredCache.rows = scoped.filter { row in
            (accountFilter == nil || row.account.id == accountFilter)
                && (!mineOnly || isMine(row))
                && PadListLogic.matches(row.item, criteria: criteria, now: now, display: directory.display)
        }
    }

    /// Whether `row`'s pad is owned by its own account's user. Ownership is account
    /// scoped, so "mine" is compared against each pad's source account.
    func isMine(_ row: AccountScoped<Pad>) -> Bool {
        row.account.owns(row.item.ownerEmail)
    }

    func pad(forID id: String) -> Pad? {
        for pads in padsByAccount.values {
            if let match = pads.first(where: { $0.id == id }) { return match }
        }
        return nil
    }

    /// The pad to select after the pad with `id` is deleted: the next visible row,
    /// then the previous, mirroring `PadsView.neighborSelection`.
    func neighborSelection(forDeleted id: String) -> Pad? {
        let visible = filtered.map(\.item)
        guard let index = visible.firstIndex(where: { $0.id == id }) else { return visible.first }
        if visible.indices.contains(index + 1) { return visible[index + 1] }
        if visible.indices.contains(index - 1) { return visible[index - 1] }
        return nil
    }

    // MARK: - Options

    var availableStates: [PadState] {
        Array(Set(scoped.map(\.item.status))).sorted { $0.label < $1.label }
    }

    var availableLanguages: [String] {
        Array(Set(scoped.compactMap { $0.item.language?.lowercased() }).filter { !$0.isEmpty }).sorted()
    }

    var availableOwners: [String] {
        Array(Set(scoped.map(\.item.ownerEmail)).filter { !$0.isEmpty }).sorted()
    }

    var activeFilterCount: Int {
        (stateFilter != nil ? 1 : 0)
            + [languageFilter, ownerFilter, typeFilter].compactMap(\.self).count
            + (accountFilter != nil ? 1 : 0)
            + (mineOnly ? 1 : 0)
            + (updatedWindow.isActive ? 1 : 0)
            + (createdWindow.isActive ? 1 : 0)
    }

    func clearAllFilters() {
        stateFilter = nil; languageFilter = nil; ownerFilter = nil; typeFilter = nil
        accountFilter = nil; mineOnly = false
        updatedWindow = PadDateWindow(); createdWindow = PadDateWindow()
    }

    /// A change token so the `List` re-identifies (fast fresh render) whenever the
    /// filter shape changes, matching `PadsView`.
    var filterSignature: String {
        ([search, stateFilter?.rawValue, languageFilter, ownerFilter, typeFilter,
          accountFilter?.uuidString, mineOnly ? "mine" : nil]
                .map { $0 ?? "·" }
                // Include the custom bounds, not just the named range, so switching
                // between two custom date ranges actually changes the signature.
                + [updatedWindow.signatureToken, createdWindow.signatureToken])
            .joined(separator: "|")
    }

    /// A token covering the set of accounts being merged (ids + key emptiness), so
    /// the load task restarts when an account is added, removed, or has its key
    /// changed — without restarting on unrelated edits.
    var accountKey: String {
        accounts.mergeableAccounts.map { "\($0.id.uuidString):\($0.apiKey.isEmpty ? 0 : 1)" }
            .joined(separator: ",")
    }

    // MARK: - Loading

    /// Show the cached pads for every account immediately, before any network
    /// fetch, so the merged list is populated on appear.
    func seedFromCache() {
        for account in accounts.mergeableAccounts where padsByAccount[account.id] == nil {
            padsByAccount[account.id] = cache.get(account.id)
        }
        publishRoutes()
    }

    /// Fan out a fresh fetch across every account concurrently. Each account's
    /// result is applied as it lands (so fast accounts show first), and one
    /// account's failure is recorded without disturbing the others.
    func reload() async {
        let mergeable = accounts.mergeableAccounts.filter { !$0.apiKey.isEmpty }
        guard !mergeable.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        // Build the clients on the main actor; each is Sendable, so the concurrent
        // children below can hold one without crossing isolation to build it.
        let targets = mergeable.map { (id: $0.id, client: $0.makeClient()) }
        await withTaskGroup(of: (UUID, [Pad]?, String?).self) { group in
            for target in targets {
                group.addTask {
                    do {
                        let pads = try await target.client.listPads(sort: "updated_at,desc")
                        return (target.id, pads, nil)
                    } catch {
                        return (target.id, nil, error.localizedDescription)
                    }
                }
            }
            for await (id, pads, errorText) in group {
                if let pads {
                    padsByAccount[id] = pads
                    accountErrors[id] = nil
                    cache.set(id, pads: pads)
                } else {
                    accountErrors[id] = errorText
                }
                publishRoutes()
                isLoading = false
            }
        }
        // Cold start with empty caches: the list first appears here, so this is the
        // earliest the saved selection can be resolved. Idempotent (guarded by
        // `didRestoreSelection`), so the per-refresh calls after this are no-ops.
        restoreSelectedPadIfNeeded()
    }

    /// Publish the pad -> account map so the detail pane and row actions can route
    /// to the right client.
    func publishRoutes() {
        var routes: [String: UUID] = [:]
        for account in accounts.mergeableAccounts {
            for pad in padsByAccount[account.id] ?? [] {
                routes[pad.id] = account.id
            }
        }
        router.setPadRoutes(routes)
    }

    // MARK: - Filter persistence

    /// The single key for the merged list's live filters. Not per-account — the
    /// merged list spans every account — unlike `PadsView`'s per-account key.
    static var liveFilterKey: String { "pads.merged.liveFilter" }

    /// Snapshot the structured filters into a `NamedSearch`, reusing the same model
    /// `PadsView` persists. The cross-account `accountFilter` and the `mineOnly`
    /// preset are intentionally left out, matching how the single-account list omits
    /// its own presets; `teamFilter` has no merged equivalent, so it stays nil.
    func captureCurrentSearch() -> NamedSearch {
        NamedSearch(
            name: "", search: search,
            stateFilter: stateFilter, languageFilter: languageFilter,
            ownerFilter: ownerFilter, teamFilter: nil,
            typeFilter: typeFilter,
            updatedWindow: updatedWindow.isActive ? updatedWindow : nil,
            createdWindow: createdWindow.isActive ? createdWindow : nil
        )
    }

    /// Apply a saved snapshot to the live filters. Mirrors `PadsView.apply`, minus
    /// the team filter the merged list doesn't expose.
    func apply(_ saved: NamedSearch) {
        search = saved.search
        stateFilter = saved.stateFilter
        languageFilter = saved.languageFilter
        ownerFilter = saved.ownerFilter
        typeFilter = saved.typeFilter
        updatedWindow = saved.updatedWindow ?? PadDateWindow()
        createdWindow = saved.createdWindow ?? PadDateWindow()
    }

    /// Persist the current filters so the merged list reopens with the same view.
    /// Skipped until the initial restore has run, so the empty startup state never
    /// clobbers a saved snapshot.
    func persistFilters() {
        guard didRestoreFilters else { return }
        if let data = try? JSONEncoder().encode(captureCurrentSearch()) {
            UserDefaults.standard.set(data, forKey: Self.liveFilterKey)
        }
    }

    /// Restore the persisted filters once, on appear.
    func restoreFilters() {
        guard !didRestoreFilters else { return }
        didRestoreFilters = true
        guard let data = UserDefaults.standard.data(forKey: Self.liveFilterKey),
              let snapshot = try? JSONDecoder().decode(NamedSearch.self, from: data) else { return }
        apply(snapshot)
    }

    // MARK: - Selection persistence

    /// The single key for the merged list's open pad. Pad ids are globally unique
    /// across accounts, so the merged selection needs no account namespacing (unlike
    /// merged questions, whose per-org ids collide and must carry their account).
    static var selectedPadKey: String { "pads.merged.selectedPad" }

    /// Persist the id of the pad shown in the detail pane so the merged list reopens
    /// to it next launch. Skipped until the restore has run so the empty startup
    /// state can't clobber the saved id; clearing the selection removes the stored id
    /// so a blank detail pane is restored faithfully too.
    func persistSelectedPad() {
        guard didRestoreSelection else { return }
        if let selectedID {
            UserDefaults.standard.set(selectedID, forKey: Self.selectedPadKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.selectedPadKey)
        }
    }

    /// Restore the previously-open pad once a list exists to resolve it against.
    /// Marks the restore complete as soon as pads load (so later changes persist),
    /// then reselects via `PadsView.padToRestore` — the same pure, unit-tested
    /// decision the single-account list uses. Reads the source dictionary rather than
    /// the per-render `scoped` memo, which can still be empty right after a cache seed.
    func restoreSelectedPadIfNeeded() {
        let availableIDs = Set(padsByAccount.values.flatMap { $0 }.map(\.id))
        guard !didRestoreSelection, !availableIDs.isEmpty else { return }
        didRestoreSelection = true
        guard let id = PadsView.padToRestore(
            savedID: UserDefaults.standard.string(forKey: Self.selectedPadKey),
            hasSelection: selection != nil,
            hasPendingOpen: router.pendingFavoritePadID != nil,
            availableIDs: availableIDs
        ) else { return }
        selectedIDs = [id]
        // Bring the restored row into view; the List won't scroll to it on its own.
        pendingScrollToID = id
    }

    // MARK: - Mutations

    func applyUpdated(_ pad: Pad) {
        guard let accountID = router.padAccountID[pad.id],
              var pads = padsByAccount[accountID],
              let index = pads.firstIndex(where: { $0.id == pad.id }) else { return }
        pads[index] = pad
        padsByAccount[accountID] = pads
        if selection?.id == pad.id { selection = pad }
    }

    func removePad(id: String) {
        for (accountID, pads) in padsByAccount where pads.contains(where: { $0.id == id }) {
            padsByAccount[accountID] = pads.filter { $0.id != id }
        }
        publishRoutes()
    }

    func insert(_ pad: Pad, into account: Account) {
        var pads = padsByAccount[account.id] ?? []
        pads.insert(pad, at: 0)
        padsByAccount[account.id] = pads
        cache.set(account.id, pads: pads)
        publishRoutes()
    }

    // MARK: - Actions

    func openPad(_ pad: Pad) {
        guard let url = pad.webURL else { return }
        if BrowserSettings.openLinksIn == .external {
            BrowserSettings.openExternally(url)
        } else {
            openWindow(id: "pad-browser", value: url)
        }
    }

    func deletePad(_ pad: Pad) async {
        let client = (router.account(forPadID: pad.id) ?? accounts.currentAccount)?.makeClient()
        guard let client else { return }
        do {
            try await client.deletePad(id: pad.id)
            AppRouter.padDeleted(id: pad.id)
        } catch {
            deleteError = error.localizedDescription
        }
    }

}
